# Eastern Broadleaf Preflight

**Retired on 2026-09-18:** see the [HARV/BART closeout](../docs/harv-bart-closeout.md).
Findings and reproduction notes below are historical diagnostics. No further
eastern investigation or validation is planned; unresolved gates remain.

## Status and Scope

Authentication, exact-year field preparation, released-file inventories and a
bounded HARV LiDAR/RGB smoke check are complete. **Reference support remains
unverified, and no eastern detector results or frozen eligible split exist.**
HARV is reserved for development/pilot and BART for held-out validation under
the [predeclared protocol](../docs/eastern-preflight-protocol.md). No model,
fusion, calibration fit, or BART performance inspection was run.

Public metadata was archived on **2026-09-15 at 14:47:44 UTC**. It identifies
August 2022 as the earliest common LiDAR/RGB acquisition year since the
2021 baseline. Neither site lists 2021 AOP availability. These come from
the [HARV](https://data.neonscience.org/api/v0/sites/HARV) and
[BART](https://data.neonscience.org/api/v0/sites/BART) product listings.

## Verified Metadata

| Site | Role | LiDAR / RGB month | Field-product months in 2022 | WGS84 EPSG |
| --- | --- | --- | --- | --- |
| HARV | Development | 2022-08 / 2022-08 | July, August, September, October | 32618 |
| BART | Held out | 2022-08 / 2022-08 | July, August, September | 32619 |

The [HARV location record](https://data.neonscience.org/api/v0/locations/HARV)
declares WGS84 UTM 18N, while the
[BART location record](https://data.neonscience.org/api/v0/locations/BART)
declares WGS84 UTM 19N. HARV_033's downloaded field, LAS and RGB headers agree
on EPSG:32618. Header agreement does not establish absolute positional accuracy
or reconcile the product-level datum specification discussed below.

## Authenticated Data Inventory

After `NEON_TOKEN` was configured outside the repository, protected requests
returned HTTP 200. The earlier unauthenticated HTTP 403 is resolved.
[NEON authentication guidance](https://data.neonscience.org/data-api/authentication/)
requires tokens for data downloads while keeping site/location metadata open.
Credentials belong in the process environment or user-managed `~/.Renviron`,
not in scripts, manifests, reports, or Git history. Signed cloud URLs are also
credentials and are excluded from archived file lists.

Field preparation used `YEAR=2022 MAX_YEAR_GAP=0`, release `RELEASE-2026`, in a
separate eastern job directory. Counts below distinguish all-year location
preparation from the exact-year candidate population.

| Site | Mappable stems, all years | Geolocated | Failed named points / excluded stems | Exact-2022 live trees | Inside nominal candidate boxes |
| --- | --- | --- | --- | --- | --- |
| HARV | 2,744 | 2,644 | 8 / 100 | 251 | 227 across five plots |
| BART | 2,134 | 2,108 | 12 / 26 | 269 | 257 across five plots |

Named-point requests that failed with HTTP 400 were excluded, not imputed as
absent trees. Counts inside boxes additionally require finite positive height
and coordinates. The audit retains all 42 HARV and 41 BART plot rows; the other
37 and 36 plots respectively have no exact-2022 census event in this cache.

The refreshed file-identity snapshots were retrieved on **2026-09-15 at
16:40:28-31 UTC** for `2022-08`, `RELEASE-2026`:

| Site | Product | Listed files | Recognized 1 km spatial tiles |
| --- | --- | --- | --- |
| HARV | LiDAR, DP1.30003.001 | 532 | 359 |
| HARV | RGB, DP3.30010.001 | 363 | 361 |
| BART | LiDAR, DP1.30003.001 | 317 | 156 |
| BART | RGB, DP3.30010.001 | 161 | 158 |

All ten count-qualified plots have listed LiDAR and RGB tiles through their
nominal box plus 25 m buffer. The coverage check includes every intersected
tile, including the northern neighbor at BART_071. Listed coverage is not a
physical-data audit of every tile. Only HARV_033 spatial data was downloaded;
**no BART LiDAR/RGB tiles or detector outputs were inspected**.

## Reference-Support Blocker

Every candidate has `eventType=towerSubset` and `totalSampledAreaTrees=800`,
not the 1600 m2 implied by the historical full tower box. The July 14 censuses
are `vst_HARV_2022` and `vst_BART_2022`. Protocol versions are K, except
BART_036 and BART_073, which record J.

| Plot | Exact-year trees inside nominal box | Sampled subplots |
| --- | --- | --- |
| HARV_033 | 31 | 21_400, 23_400 |
| HARV_034 | 61 | 23_400, 39_400 |
| HARV_038 | 61 | 23_400, 39_400 |
| HARV_039 | 39 | 39_400, 41_400 |
| HARV_040 | 35 | 23_400, 41_400 |
| BART_036 | 52 | 21_400, 41_400 |
| BART_040 | 39 | 21_400, 41_400 |
| BART_042 | 52 | 39_400, 41_400 |
| BART_071 | 50 | 21_400, 39_400 |
| BART_073 | 64 | 23_400, 39_400 |

The [NEON vegetation structure guide](https://data.neonscience.org/api/v0/documents/NEON_vegStructure_userGuide_vE.1)
describes two randomly selected 20 m square subplots within forest tower plots.
Smaller stems can use nested sampling, so a total area alone cannot establish
reference completeness for every growth form or diameter class.

**Do not score the full tower box against this partial census.** Reconstruct
event-specific sampled footprints and declare the target population before
calibration, pilot scoring or split freezing. Missing or ambiguous census
metadata fails the audit; even a nominal-area match remains unverified until
geometry and population checks pass. The current scorer and historical D17
results are unchanged. Their event-specific supports need a separate audit,
not an automatic regrade or a claim that ensemble agreement supplies truth.

## HARV Spatial Smoke

HARV_033 was selected lexicographically from count/tile candidates at
**16:30:00 UTC**, before density inspection. The original selection receipt
has MD5 `7be45e6de27340444c15cbb0ef5c2518`; its inventory MD5 is
`9bc669b1996770595f494b5159455c15`. The later support-aware audit reproduces
that diagnostic selection without approving its box for scoring.

One LiDAR tile and one RGB tile cover the entire 90 m square buffered clip:

| File | Bytes | Local MD5 |
| --- | --- | --- |
| NEON_D01_HARV_DP1_731000_4713000_classified_point_cloud_colorized.laz | 197,809,451 | `c8941c374050a60a53be9da2c990d60c` |
| 2022_HARV_7_731000_4713000_image.tif | 351,068,547 | `4323cb1a578d84092b563cce0264eafd` |

These are local provenance hashes, not independently verified API MD5 values:
the file listings do not supply MD5 for these objects. The RGB has three bands
and 0.1 m cells. LAS horizontal and vertical coordinate units are metres.

| Diagnostic | Measured value |
| --- | --- |
| Density measurement area | 8,100 m2, nominal 40 m box plus 25 m buffer on each side |
| Raw / normalized points | 103,882 / 103,881 |
| Raw ground-class points | 6,781 |
| Raw all-return density | 12.82494 points/m2 |
| Normalized all-return density | 12.82481 points/m2 |
| Raw and normalized first-return density | 4.86444 first returns/m2 |
| Normalized height range | -0.07 to 33.20 m |
| Raw / normalized withheld points retained | 220 / 219 |
| Detector, calibration, held-out scoring runs | Zero |

The raw class counts are 1: 1,567; 2: 6,781; 5: 95,534. This smoke preserves
the existing point-filter policy, including withheld points. It does not
silently revise historical density measurements. Numeric rungs 8, 4, 2 and 1
are below this clip's native **all-return** density; they are not validated
for every plot or interchangeable with first-return density.

Manual review of `rgb_core_review.png` shows green, leaf-on canopy and mapped
stems confined to the southern half of the nominal box, consistent with the
census metadata. This is qualitative imagery review, not a quantified
greenness fraction or a positional-accuracy validation.

The [official flight table](https://www.neonscience.org/data-collection/flight-schedules-coverage)
lists HARV visit 7 on August 3, 4, 12 and 14, 2022, and BART visit 6 on August
19 and 20. Both used Riegl LMS-Q780 unit 2220855. The smoke LAS stores GPS
week time, not a complete date. Its file-creation date is processing metadata;
an exact contributing-flight date still needs authoritative reconciliation.

The [LiDAR product specification](https://data.neonscience.org/api/v0/products/DP1.30003.001)
describes ITRF00 horizontal coordinates and NAVD88/Geoid12A elevations. Resolve
that specification against the WGS84 field/header declarations before using
metre-scale match residuals as accuracy evidence. TIN-normalized heights here
are above-ground heights, not the original absolute elevations.

## Implementation and Boundaries

- `preflight_eastern_sites.R` archives four public metadata responses, hashes
  them, records the protocol/code declaration and writes product-month/site
  inventories. Cached replay checks archive integrity without network access.
  `MODE=references` lists local exact-year field candidates without choosing a
  smoke plot or freezing eligibility.
- `neon_ground_truth.R` accepts `YEAR` and `MAX_YEAR_GAP`, records acquisition
  and measurement epochs plus UTM/EPSG, and selects measurements and centroid
  observations nearest the target year. Defaults remain 2021 and four years.
  `dist21` remains literal; the new `dist_aop` follows the requested year.
- Both downloaders pass the external token through `neonUtilities`, support
  `PLOTS=`, and bind caches to product/year/CRS/provisional policy. Queries use
  plot centres plus 50 m, covering the 45 m maximum core-plus-buffer reach.
  Downloaded spatial headers must match the field frame.
- `neon_acquisition_lib.R` supplies the omitted token on the first internal
  file-list call in installed `neonUtilities` 3.0.3. The wrapper preserves the
  upstream tile selector and does not alter its installed namespace. Both real
  downloads pass; archive helpers never persist signed URLs.
- `preflight_eastern_coverage.R` archives released file identities, checks
  buffered tile availability and reports census event/subplot/area support.
  `preflight_harv_smoke.R` checks the union of actual tile extents, clips and
  normalizes the declared HARV plot, and exports density and RGB diagnostics.
  Neither freezes eligibility or runs a detector.
- All NEON catalog-loading detection, height and crown entry points use the
  shared field/acquisition/header guard. Every input LAS header is checked,
  so a mixed-zone catalog cannot hide behind its first tile's CRS. The shared
  UTM-11N constant is removed. GeoJSON exporters and EPT discovery derive the
  frame from plot metadata; RGB arms also check raster and frozen-CHM CRS.
- Frozen clips bind reuse to site/plot/rung, CRS, centre, core, buffer and
  source file identity. All three spatial outputs must exist and match CRS.
  Source identity uses canonical paths, sizes and modification times, not a
  content checksum of every large tile. RGB prediction caches similarly
  record source identity and coordinate context.
- Unversioned, incomplete or incompatible caches fail without overwriting
  historical files. Regenerate in a fresh `CLAUDE_JOB_DIR`/output root, never
  fabricate manifests for old artifacts. Historical 2021 acquisition inputs
  remain readable by guarded consumers; this is not a new epoch verification
  of those artifacts. Read-only result analyses are unchanged.
- The native-QL2 cross-check remains explicitly D17-only. Three historical
  crown-reference joins still target 2021 and reject other acquisition years.
  This work does not promote those workflows to eastern evaluation or audit
  every downstream reader of already-generated prediction tables.

## Reproduction and Verification

The original public metadata snapshot and its offline replay used
`work/eastern_preflight`. Its declaration predates the sampled-area protocol
amendment and is preserved, not rewritten to match the newer code. Use a fresh
output root to regenerate a declaration under the current protocol.

Authenticated preparation and the support-aware smoke use:

```sh
export CLAUDE_JOB_DIR="$PWD/work/eastern-study-2022"
for SITE in HARV BART; do
  Rscript scripts/neon_ground_truth.R SITE="$SITE" YEAR=2022 MAX_YEAR_GAP=0
done
AUDIT="$CLAUDE_JOB_DIR/authenticated_preflight_v2"
Rscript scripts/preflight_eastern_coverage.R MODE=coverage OUT="$AUDIT"
Rscript scripts/neon_download_lidar.R SITE=HARV YEAR=2022 PLOTS=HARV_033
Rscript scripts/neon_download_aop.R SITE=HARV YEAR=2022 PLOTS=HARV_033
Rscript scripts/preflight_harv_smoke.R AUDIT="$AUDIT"
Rscript tests/run_tests.R
rumdl check --no-cache .
git diff --check
```

The authenticated audit contains file-list snapshots, a code/input/protocol
contract, `released_availability.csv`, `plot_coverage_candidates.csv`,
`sampling_support.csv`, `smoke_selection.json`, and `smoke/HARV_033/` with
the frozen native clip, summary and RGB review. The initial diagnostic run in
`authenticated_preflight/` remains unchanged. Generated artifacts stay outside
version control. Field RDS hashes are HARV `058aa8b56af7cbaad456c56279385cf0`
and BART `d188700b0010287ee8fc5799569a5746`.

The four original public response MD5 values describe the inspected snapshot,
not permanent API checksums:

| Response | MD5 |
| --- | --- |
| HARV site | `340235f357edc41d89c36fcce992ca3c` |
| HARV location | `18908f9c93a53afe5c4f975262e82a32` |
| BART site | `e902356d942f31e5a6414dc09c77f9e2` |
| BART location | `ec8610763b3492ab51bf5421d84bc4bb` |

The full R suite passes, including synthetic cross-zone coordinate round trips,
LAS/RGB mismatch rejection, epoch/cache rejection without file modification,
real synthetic frozen-clip creation/replay, and score-blind metadata/field
eligibility cases. Three tests skip: gated live ForestFormer3D inference,
an empty-LAS writer fixture, and optional Python `plyfile` interoperability.
An optional R-universe index probe warns because it cannot access the network.
New regressions cover the omitted-token path, signed-URL exclusion, tile-edge
coverage, catalog gaps, partial/missing/ambiguous census metadata and refusal
to infer complete support from sampled area alone. These tests and the actual
HARV diagnostic do not complete the remaining reference and datum audit.

## Historical Following Work (Retired)

The [event-specific support follow-up](neon-reference-support-results.md) now
implements geometry/reference auditing and optional polygon scoring, with a
read-only D17 census audit. Its actual bundles remain diagnostic-only.

1. Resolve the follow-up's missing target references and subplot conflicts under
   a declared policy. Do not admit incomplete support or overwrite historical
   results simply because a measured polygon is now available.
2. Resolve field/AOP datum and exact contributing-flight provenance, then
   complete remaining physical coverage and per-plot density checks. Keep
   BART metadata-only until its declared data-preparation step.
3. Freeze supported plot IDs, rungs and the HARV/BART split before fitting or
   model selection. Synthetic detection-only interface work can proceed, but
   no full-box pilot scoring or calibration is authorized by this smoke.
4. Run the declared HARV development comparison, then evaluate the frozen
   pipeline on BART. No optical/deep-model advantage is inferred here.
