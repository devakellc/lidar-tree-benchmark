# Findings so far (2026-10-16)

## 3DEP EPT access

- The public bucket `s3-us-west-2.amazonaws.com/usgs-lidar-public/<project>/ept.json`
  is readable directly by lasR (`exec(reader_rectangles(...) + ..., on = url)`).
  No PDAL needed for acquisition.
- lasR built from `r-lidar/lasR@pre-devel` reports version 0.21.0. It has
  `reader_rectangles`, `summarise(metrics = ...)`, `normalize`, `triangulate`,
  `rasterize`, `pit_fill`, `focal` (mean/median only), `local_maximum_raster`
  (with `ws` as a function), `region_growing`, `load_raster` and `callback`.
  It has no reprojection stage.
- `summarise(metrics = c("gpstime_min", "gpstime_max", "count"))` works on an
  EPT and returns per-chunk values. For the Carr/Hirz/Delta AOI the adjusted
  GPS time is about 2.56e8 s, i.e. late October 2019; `mck_leaburg` was
  flown on 2021-07-05.
- Densities from `summarise()` on an EPT are per Web Mercator square unit.
  Multiply by k² = 1 / cos²(latitude) for true ground density. The repository's
  `detect_lasr_ept_aoi.R` does not apply this, which is consistent with its
  note that the EPT path is for acquisition benchmarking only.

## AOI scouting

200 m ground squares, first returns, normalized heights. Densities are true
ground pulses/m² (reported × k²). Shares are fractions of first returns.

| id | EPT project | lon, lat | pulses/m² | > 2 m | 1.5–5 m | 5–15 m | > 15 m |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| carr_toy | CA_CarrHirzDeltaFires_2_2019 | −121.9731, 40.8443 | 15.1 | 0.90 | 0.063 | 0.45 | 0.40 |
| mck_marcola | OR_McKenzieRiver_1_2021 | −122.80, 44.17 | 15.5 | 0.69 | 0.034 | 0.20 | 0.47 |
| mck_leaburg | OR_McKenzieRiver_1_2021 | −122.62, 44.11 | 20.0 | 0.14 | 0.098 | 0.06 | 0.00 |
| wwf_mill | OR_WWildfires_1_A22 | −122.40, 44.75 | 10.7 | 0.56 | 0.012 | 0.07 | 0.49 |
| wwf_glide | OR_WWildfires_1_A22 | −122.85, 43.30 | no points | | | | |
| sn_arnold | CA_SierraNevada_3_2022 | −120.35, 38.25 | no points | | | | |
| sn_pollock | CA_SierraNevada_3_2022 | −120.58, 38.75 | no points | | | | |

Reading: `mck_leaburg` looks like young regeneration (14 % of returns above
2 m, about 10 % in 1.5–5 m) and is the best small-tree candidate so far.
`carr_toy` (the lidar_tree_benchmarks toy AOI) and `mck_marcola` are mature
closed canopy; `wwf_mill` is mature with gaps. The three "no points" centres
fall outside the irregular project footprints even though they are inside the
`ept.json` bounding boxes; choose points from the footprint index
(`hobuinc/usgs-lidar` `resources.geojson`) instead.

A balanced first set would be two CA and two OR AOIs mixing one regeneration
and one mature area per state. A CA regeneration AOI is still missing; the
Carr fire (2018) footprint inside `CA_CarrHirzDeltaFires_2_2019` is too
recent for saplings at the 2019 flight, so look at older harvest units in the
same project or `CA_NoCAL_Wildfires_*_2018`.

Other recent OR projects in the bucket: `OR_SWCentralSycan_*_B21`,
`OR_UmatillaWallowaWhitman_1_B22`, `OR_UpperJohnDay_1_2020`,
`OR_Klamath_2018`. CA: `CA_SierraNevada_1..14_2022`, `CA_NorthernCA_1..8_B22`,
`CA_LassenNP_2020`, `CA_UpperSouthAmerican_Eldorado_2019`.

Timing: about 40 s per 200 m square through a single connection. A query that
finds no files can still take minutes while the EPT hierarchy is walked
(`sn_pollock` took 530 s).

## Environment notes from this run

- Ubuntu 24.04 apt has R 4.3.3, terra, sf, data.table, clue, testthat, but
  not lidR or PDAL. lasR pre-devel builds from source against apt's GDAL,
  GEOS, PROJ and sqlite headers in a few minutes.
- The cloud container used here could not reach Planetary Computer, NEON,
  CRAN or Hugging Face, and had no GPU, which is why the run moved to another
  machine.
