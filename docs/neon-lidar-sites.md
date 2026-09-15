# NEON benchmark sites — field data & LiDAR acquisitions

Reference for the three **Domain D17 (Pacific Southwest)** sites used in the
density-ladder sweep and follow-on analyses, plus the eastern preflight.
The three D17 sites share **UTM zone 11N / EPSG:32611** for NEON woody-vegetation
and AOP LiDAR products. That frame does not apply to HARV or BART.

**Field ground truth:** NEON Woody Plant Vegetation Structure `DP1.10098.001`
(mapped stems >10 cm DBH in 20×20 m distributed and 40×40 m tower plots).
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
| SJER | 2013-06, 2017-03, 2018-03, 2019-03, **2021-03**, 2023-04, 2024-04 | **2021-03** | Optech Galaxy Prime (~20 pts/m² class) | 16.3 | 9.0 |
| SOAP | 2013-06, 2017-07, 2018-06, 2019-06, **2021-07**, 2023-06, 2023-07, 2024-06, 2026-04 | **2021-07** | Optech Galaxy Prime (~20 pts/m² class) | 18.2 | 11.9 |
| TEAK | 2013-06, 2017-06, 2018-06, 2019-06, **2021-07**, 2023-07, 2024-06 | **2021-07** | Optech Galaxy Prime (~20 pts/m² class) | 19.2 | 11.9 |

**Sensor timeline (NEON airborne).** Optech Gemini era (2013–2020) yields
~4–6 pts/m² at these sites; **2021+ Galaxy Prime** is the first acquisition
that clears the repository's >8 pts/m² design threshold. Pre-2021 site-years
remain on the portal but are not used in the benchmark pipeline.

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

## Eastern broadleaf preflight

The score-blind inventory retrieved public metadata on 2026-09-15. These are
availability and coordinate facts, not detection results or verified plot
coverage. Sources: [HARV metadata](https://data.neonscience.org/api/v0/sites/HARV),
[BART metadata](https://data.neonscience.org/api/v0/sites/BART), and the
[HARV](https://data.neonscience.org/api/v0/locations/HARV) /
[BART](https://data.neonscience.org/api/v0/locations/BART) location records.

| Site | Declared role | WGS84 UTM frame | Selected LiDAR/RGB month | Native density / eligible plots |
| --- | --- | --- | --- | --- |
| HARV, Harvard Forest | Development and pilot | 18N, EPSG:32618 | 2022-08 | Pending data checks |
| BART, Bartlett Experimental Forest | Held-out site validation | 19N, EPSG:32619 | 2022-08 | Pending data checks |

Neither site lists 2021 LiDAR or RGB data. The earliest common acquisition year
at or after 2021 is 2022. Both list AOP months in 2014, 2016, 2017, 2018, 2019,
2022, 2024 and 2025. Field-product listings include July-October 2022 at HARV
and July-September at BART, but these months do not establish exact-year mapped
live-tree coverage. August timing does not independently establish leaf-on
status for a particular tile or flight.

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
