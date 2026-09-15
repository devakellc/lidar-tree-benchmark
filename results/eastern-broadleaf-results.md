# Eastern Broadleaf Preflight

## Status and Scope

The score-blind metadata and coordinate-safety implementation is complete.
**The data preflight is not complete, and no eastern detector results exist.**
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
declares WGS84 UTM 19N. Actual field, LAS and RGB alignment still requires the
downloaded inputs. Public field-product months and named locations do not
establish eligible plots or reference counts.

## Access and Unfinished Checks

The unauthenticated HARV LiDAR file-list request for August 2022 returned
HTTP 403, `Access Denied`. `NEON_TOKEN` was not configured during verification.
[NEON authentication guidance](https://data.neonscience.org/data-api/authentication/)
requires tokens for data downloads while keeping site/location metadata open.
Credentials belong in the process environment or user-managed `~/.Renviron`,
not in scripts, URLs, manifests, reports, or Git history.

| Check | Result |
| --- | --- |
| Acquisition availability and declared site CRS | Verified from public metadata |
| Exact-year field stems and eligible plot IDs | Pending authenticated data and reference audit |
| LiDAR/RGB tile coverage and actual header alignment | Pending downloads |
| Native all-return and first-return density | Not measured |
| Actual acquisition dates and leaf-on confirmation | Pending flight/tile and phenology evidence |
| HARV smoke plot and frozen HARV/BART eligible split | Not selected or frozen |
| Candidate numeric density rungs | 8, 4, 2, 1; eligibility requires measured native all-return density |
| Detection, fusion, calibration and held-out metrics | Not run |

NEON schedules flights around peak foliar greenness, but that policy and an
August listing are not proof of the selected flight's leaf-on condition.
Consult the [flight coverage guidance](https://www.neonscience.org/data-collection/flight-schedules-coverage)
alongside the eventual tile/flight metadata.

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

From the implementation worktree, the metadata run and its offline replay used
the same output directory:

```sh
Rscript scripts/preflight_eastern_sites.R OUT=work/eastern_preflight
Rscript tests/run_tests.R
rumdl check --no-cache .
git diff --check
```

The generated directory contains `metadata/`, `metadata_manifest.json`,
`declaration.json`, `site_inventory.csv` and `available_months.csv`. Generated
artifacts stay outside version control. The four archived response MD5 values
are recorded here for the inspected snapshot, not as permanent API checksums:

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
These tests do not substitute for an actual HARV smoke plot.

## Following Work

1. Configure `NEON_TOKEN` outside the repository and prepare exact-2022 field
   references in a fresh eastern job directory; archive authenticated file
   metadata and report exclusions and available plot coverage.
2. Select the score-blind HARV smoke plot after coverage checks. Verify actual
   CRS/epoch alignment, leaf-on condition and both native density units.
3. Freeze all eligible plot IDs, supported rungs and the HARV/BART split before
   model selection. Keep BART score-blind throughout development.
4. Proceed to the declared detection-only comparison and bounded HARV pilot,
   then evaluate the frozen pipeline on BART. Do not infer an optical or
   deep-model advantage from this metadata work.
