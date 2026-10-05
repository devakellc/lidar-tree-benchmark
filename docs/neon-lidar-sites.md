# NEON benchmark sites — field data & LiDAR acquisitions

Reference for the three **Domain D17 (Pacific Southwest)** sites used in the
density-ladder sweep and follow-on analyses, the two **Domain D16 (Pacific
Northwest)** sites admitted to extend it, and the retired eastern preflight.
The three D17 sites share **UTM zone 11N / EPSG:32611** for NEON woody-vegetation
and AOP LiDAR products. That frame does not apply to WREF, ABBY, HARV or BART.

**Field ground truth:** NEON Woody Plant Vegetation Structure `DP1.10098.001`.
Nominal plot dimensions do not establish census coverage: forest tower plots
can sample only two 20×20 m subplots within a 40×40 m box. Sampling and mapping
depend on growth form, diameter and census event. Audit those supports before
interpreting full-box precision; historical D17 metrics are not regraded here.
See the [vegetation structure guide](https://data.neonscience.org/api/v0/documents/NEON_vegStructure_userGuide_vE.1).
**Airborne LiDAR (primary):** NEON discrete-return point cloud `DP1.30003.001`
(AOP tiles via `neon_download_lidar.R`, restricted to 1 km tiles overlapping
field plots). **Cross-check LiDAR:** USGS 3DEP public EPT projects
([`ept_discovery.R`](../scripts/ept_discovery.R)).

Acquisition months below are from the NEON Data Portal API
(`GET /api/v0/sites/{SITE}`, product `DP1.30003.001`) as of 2026-06-10.

---

## Site overview

| Code | Site name | Forest type (benchmark role) | Lat, lon | Benchmark plots / live stems† |
|------|-----------|------------------------------|----------|-------------------------------|
| **SJER** | San Joaquin Experimental Range | Open oak / foothill-pine woodland (open-canopy gradient) | 37.11°N, 119.73°W | 8 / 71 |
| **SOAP** | Soaproot Saddle | Mixed conifer/deciduous (**anchor** site) | 37.03°N, 119.26°W | 18 / 232 |
| **TEAK** | Lower Teakettle | Red fir / subalpine conifer (dense-canopy gradient) | 37.01°N, 119.01°W | 20 / 396 |

†Live, mapped tree stems in the sweep ground truth (`ground_truth_stems.csv`),
paired with the **2021** NEON AOP acquisition (±4 yr nearest field measurement).

---

## NEON AOP LiDAR (`DP1.30003.001`)

| Site | All portal acquisition months | Benchmark acquisition | Sensor (benchmark year) | Native all-return pts/m² | Native first-return pts/m² |
|------|------------------------------|----------------------|-------------------------|:------------------------:|:--------------------------:|
| SJER | 2013-06, 2017-03, 2018-03, 2019-03, **2021-03**, 2023-04, 2024-04 | **2021-03** | RIEGL Q780 2220855, payload P3C1 | 16.3 | 9.0 |
| SOAP | 2013-06, 2017-07, 2018-06, 2019-06, **2021-07**, 2023-06, 2023-07, 2024-06, 2026-04 | **2021-07** | Optech Galaxy Prime 5060445, payload P1C2 | 18.2 | 11.9 |
| TEAK | 2013-06, 2017-06, 2018-06, 2019-06, **2021-07**, 2023-07, 2024-06 | **2021-07** | Optech Galaxy Prime 5060445, payload P1C2 | 19.2 | 11.9 |

**Sensor timeline (NEON airborne).** Optech Gemini era (2013–2020) yields
~4–6 pts/m² at these sites; the 2021 acquisitions are the first to clear the
repository's >8 pts/m² design threshold. They come from two instruments: NEON's
2021 L3 discrete-LiDAR processing reports state that SOAP and TEAK were "flown
with Teledyne Optech Galaxy Prime 5060445 as part of payload P1C2" and SJER
"with RIEGL LASER MEASUREMENT SYSTEMS Q780 2220855 as part of payload P3C1".
SJER's tiles also come from a different processing chain (LAS 1.3, point
format 3, against LAS 1.4, point format 7 at SOAP and TEAK). Pre-2021
site-years remain on the portal but are not used in the benchmark pipeline.

**Download:** `Rscript scripts/neon_download_lidar.R SITE=<CODE> YEAR=2021`
(after `neon_ground_truth.R`).

---

## USGS 3DEP LiDAR (native QL2 cross-check)

Public entwine EPT projects covering each site (preferred project per
[`native-ql2-crosscheck-results.md`](../results/native-ql2-crosscheck-results.md)):

| Site | Covering EPT project(s) | Acquisition (from project name) | Median native first-return pts/m² over plots | Notes |
|------|-------------------------|---------------------------------|:--------------------------------------------:|-------|
| SOAP | `CA_SierraNevada_14_B22` | **2022** (Sierra Nevada block B22) | ~44 | Only one public project; no QL2-tagged alternative |
| SJER | `CA_FEMAR9Fresno_2_2019`, `CA_SierraNevada_11_B22` | **2019** (preferred QL2), 2022 (alt.) | ~5.5 | Discovery prefers the QL2-tagged 2019 project |
| TEAK | `CA_SierraNevada_14_B22` | **2022** (Sierra Nevada block B22) | ~31 | Same high-density block as SOAP |

EPT tiles are stored in **EPSG:3857** (Web Mercator); metric detection reprojects
to UTM 11N before CHM construction ([`extract.json`](../scripts/extract.json)
/ `native_ql2_crosscheck.R`).

---

## Field measurement timing vs. 2021 LiDAR

Ground truth pairs each stem with the `apparentindividual` record **nearest
2021 within ±4 yr** (`neon_ground_truth.R`: `meas_year`, `dist21`). Exact-2021
field coverage:

| Site | Mapped live-tree stems | Measured in 2021 | Exact-2021 share |
|------|:----------------------:|:----------------:|:----------------:|
| TEAK | 483 | 233 | 48% |
| SOAP | 268 | 52 | 19% |
| SJER | 113 | 0 | 0% |

SJER field stems were mostly measured in **2022 and 2024**, not 2021; treat its
sweep metrics as carrying the full ±4 yr temporal slack.

## Pacific Northwest extension (D16)

WREF and ABBY, in Washington, passed the
[extension preflight](../results/pacific-northwest-extension-results.md) on
2026-10-01. Both use **UTM zone 10N / EPSG:32610** for field and LiDAR data;
do not mix their coordinates with the D17 frame.

| Code | Site name | Forest type | 2021 LiDAR | Sensor | Header tile all / first returns per m² | Admitted plots / core stems, all mapped | Same, DBH ≥ 10 cm |
|------|-----------|-------------|------------|--------|:--------------------------------------:|:---------------------------------------:|:-----------------:|
| **WREF** | Wind River Experimental Forest | Old-growth Douglas-fir / western hemlock | **2021-07** | Optech Galaxy Prime 5060445 | 18.7 / 9.8 | 38 / 1,081 | 38 / 1,063 |
| **ABBY** | Abby Road | Managed Douglas-fir | **2021-07** | Optech Galaxy Prime 5060445 | 16.3 / 10.1 | 32 / 1,074 | 25 / 800 |

Seven ABBY distributed plots are young stands of saplings below 10 cm DBH
without a NEON canopy position, so the frozen five-site population uses the
DBH ≥ 10 cm gate at every site. Tower plots sample 800 m² of trees and
distributed plots 400 m², as at D17. WREF distributed plots were censused in
2019 and 2022, ABBY distributed plots in 2017, 2019 and 2024.

**Download:** `Rscript scripts/neon_ground_truth.R SITE=<CODE> YEAR=2021`, then
`Rscript scripts/neon_download_lidar.R SITE=<CODE> YEAR=2021`.

## Eastern broadleaf preflight

**Retired on 2026-09-18:** the HARV/BART expansion is abandoned. The
[closeout](harv-bart-closeout.md) preserves these historical observations and
merged safeguards; the former development/held-out roles are no longer an
active plan. No HARV/BART evaluation or eastern-forest validation is claimed.

The score-blind inventory retrieved public and authenticated data on
2026-09-15. These are preflight facts, not detection results or a validated
scoring footprint. Sources: [HARV metadata](https://data.neonscience.org/api/v0/sites/HARV),
[BART metadata](https://data.neonscience.org/api/v0/sites/BART), and the
[HARV](https://data.neonscience.org/api/v0/locations/HARV) /
[BART](https://data.neonscience.org/api/v0/locations/BART) location records.

| Site | Former proposed role | WGS84 UTM frame | Selected LiDAR/RGB month | Native density / eligible plots |
| --- | --- | --- | --- | --- |
| HARV, Harvard Forest | Development and pilot | 18N, EPSG:32618 | 2022-08 | HARV_033: 12.825 all / 4.864 first returns per m2; no frozen plots |
| BART, Bartlett Experimental Forest | Held-out site validation | 19N, EPSG:32619 | 2022-08 | Density unmeasured; no frozen plots |

Neither site lists 2021 LiDAR or RGB data. The earliest common acquisition year
at or after 2021 is 2022. Both list AOP months in 2014, 2016, 2017, 2018, 2019,
2022, 2024 and 2025. Field-product listings include July-October 2022 at HARV
and July-September at BART, but these months do not establish exact-year mapped
live-tree coverage. August timing does not independently establish leaf-on
status for a particular tile or flight. The HARV_033 RGB smoke was visually
reviewed and shows leaf-on canopy. No BART spatial tiles were downloaded.

Five count/tile candidates per site contain 227 HARV and 257 BART mapped,
live, finite-height exact-2022 trees inside the historical nominal boxes.
Every candidate records only 800 m² of sampled tree area. None is approved
for full-box scoring: reconstruct event-specific subplot support first.
Matching headers also need a field/AOP datum and positional-accuracy audit.

The [event-specific follow-up](../results/neon-reference-support-results.md)
now reconstructs measured polygons for those events. Conservative interiors
contain 204 HARV and 226 BART references under a different declared population;
they are not paired with the earlier counts. Missing target data and subplot
conflicts keep every bundle diagnostic-only. The historical D17 audit also
finds partial and dendrometer-only events; no historical metric was rescored.

Downloads need `NEON_TOKEN`; public site/location metadata does not. Use a
separate job directory and `YEAR=2022 MAX_YEAR_GAP=0` for exact-year reference
preparation. Do not use the 2021 D17 caches or assign their CRS to eastern
coordinates. The native-QL2 cross-check is still D17-only. See the
[protocol](eastern-preflight-protocol.md) and
[preflight findings](../results/eastern-broadleaf-results.md) for access,
coverage and split-freezing gates.

## FGI-EMIT external instance benchmark

[FGI-EMIT](https://doi.org/10.5281/zenodo.19351234) is a public, version-pinned
external dataset under CC-BY-NC-SA-4.0, not a gated NEON acquisition. It contains
19 boreal and urban forest plots in Espoo, Finland, acquired with helicopter
multispectral **ALS** in July 2023. Its 1,561 trees have manual per-point instance
annotations. The official split reserves six plots and 463 trees for testing;
the remaining 13 plots contain 1,098 trees for development.

The distributed LAS files use plot-local metric coordinates without a CRS.
Do not assign a NEON UTM zone to them. `tree_index=0` is background, and the
semantic labels are dataset-specific: class 2 is a building, not ground.
The A-D neighborhood categories are retained as published, without relabeling
them as NEON crown classes.

The [external evaluation runner](../scripts/detect_external_fgiemit.R) reuses
the installed SegmentAnyTree, ForestFormer3D, TreeisoNet, and Treeiso settings.
It exports labels on a common 3D point substrate and checks pooled instance
metrics against the archived official evaluator. See the
[external results and reproduction commands](../results/fgi-emit-external-results.md).
