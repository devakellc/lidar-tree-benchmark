# Density-routed detection pipeline

Checked on 22 October 2026 and re-banded on 17 November 2026 on the density
of the scored plot cores, after an internal review found that the bands used
density measured over the whole evaluation clip
([change of density definition](#change-of-density-definition)). The
analysis runs on the fixed evaluation clips of the five-site `adopted`
population (106 plots, 2,525 stems), at the six density levels of the paper:
native density, with a median of 9.8 first-return pulses/m² in the plot
cores, and thinned levels with core medians of 4.4, 2.2, 1.8, 1.1 and 0.6
pulses/m² (whole-clip medians 4.7, 2.5, 2.0, 1.3 and 0.6;
[core density](core-density-results.md)). The 1.8 level is the QL2 level,
thinned to 3.2 points/m² and frozen in its own root; it was declared at the
U.S. Geological Survey quality level 2 (QL2) floor by its whole-clip median
of 2.0, and 79 of its 106 plot cores lie below that floor. The analysis asks
which detector a user of national-mapping airborne LiDAR should run on a
tile, given its measured density and whether a GPU is available, and checks
the answer on the replication region.

**Post hoc.** The analysis was designed after the five-site results were
known: the bands, the candidate sets, the selection rule and the comparisons
were chosen with the density and regional results in view. The picks are made
on the California (development) cells only and checked on Washington
(replication), but the design itself is not blind to Washington. The change
to core density was made after the whole-clip picks were known; it follows
the scored area, not the picks, but it is post hoc as well. No detector is
re-run; the analysis re-pools the per-plot counts of the chance-agreement
re-score of the paper runs.

## Design

- **Bands.** Each cell, one plot at one density level, falls in a band of its
  measured first-return density inside the nominal plot core, the area that
  is scored, as a user would route a tile: A at 8 pulses/m² or more (QL1 or
  denser), B from 2 to below 8 (QL2 to QL1), and C below 2 (below QL2). The
  QL1 and QL2 floors are the aggregate nominal pulse densities of 8 and 2
  pulses/m². The core density is counted by `core_density.R` on the same
  sealed clips, with the same height filter, as the clip manifest's
  whole-clip density. Routing is per cell, so the cells of one level can
  fall in two bands: at the QL2 level, 27 cells are in band B and 79 in band
  C; at the level thinned to 4 points/m², 86 and 20; at native density, 81
  cells are in band A and 25 in band B.
- **Candidates.** The eight detectors run at every density level. A GPU route
  may use all eight; a CPU route only the five classical ones (CHM-VWF,
  `multichm`, `lmfauto`, `ptrees` and AMS3D). Compute enters the analysis only
  through these two candidate sets.
- **Selection.** In each band a route runs the candidate with the highest
  pooled F1 on the band's California cells. No tie-break was declared, so an
  exact tie would stop the run; none occurred.
- **Choices made once.** The native-only choice is each route's California
  best at the native level, used at every density: it shows the cost of
  choosing a detector at native density. The single choice is each route's
  California best over every cell, used at every density: it asks whether one
  detector chosen by the same rule does as well as a route.
- **Washington best.** In each band, the candidate with the highest F1 on the
  Washington cells. It is chosen on the data it is compared on, so its
  comparisons are descriptive.
- **Scores.** The counts of each cell are those of the chance-agreement
  re-score: the observed counts, which reproduce every detector's own results,
  and the cell's mean counts over 200 random toroidal shifts at the 4 m
  radius. Recall, precision and F1 pool summed counts over a scope's cells,
  never averaged rates. Corrected F1 is (F1 − null F1) / (1 − null F1), both
  from pooled counts. Precision is that of the nominal plot core, which counts
  unmapped trees as errors and is a lower bound.
- **Intervals.** 95% percentile intervals over the master tables' plot
  resamples: 1,000 draws, plots resampled within site, one set of draws shared
  by every detector, level, band and policy. A plot's cells at several levels
  move together, and differences are paired over the same draws. The intervals
  express plot sampling only and are not adjusted for the many contrasts; a
  difference whose interval excludes zero but ends within 0.01 of it is called
  narrow.
- **Check.** Before it writes its tables, the script recomputes every
  candidate's F1 at every level for the five sites, California and
  Washington, and stops unless the estimate and both interval bounds equal the
  master tables to 1e-9; it checks corrected F1 the same way against the
  chance-agreement re-score. All 144 rows agree. These per-level scores do not
  depend on the bands, so the check is the same in either density
  definition. It also stops unless the core-density table comes from the
  same sealed roots and its whole-clip density equals the clip manifest's in
  every scored cell.

## Regenerate

```sh
CLAUDE_JOB_DIR=$(pwd)/work/paper_runs Rscript scripts/core_density.R CORES=8
CLAUDE_JOB_DIR=$(pwd)/work/paper_runs Rscript scripts/paper_density_routing.R
# -> work/paper_runs/density_routing/: routing_{cells,bands,picks,scores,
#    contrasts,check}.csv, density_routing.md, routing_contract.json
# The whole-clip banding, kept as a sensitivity:
CLAUDE_JOB_DIR=$(pwd)/work/paper_runs Rscript scripts/paper_density_routing.R \
  DENSITY=clip OUT=$(pwd)/work/paper_runs/density_routing_clip
```

The script reads `sensitivity/null_cells.csv` and `sensitivity/null_delta.csv`
of the job directory and of the QL2 level's job directory beside it
(`paper_runs_ql2`), the clip manifests and population of the two sealed roots,
the master tables, and the core-density table (`CORE_DENSITY=`, default
`core_density/core_density.csv` of the job directory). `RUNG_JOBS=<job
dir>:<root>` locates the QL2 level elsewhere, as for `master_tables.R`.
`DENSITY=clip` bands by the clip manifest's whole-clip density instead: it
reproduces five of the six CSV files of 22 October 2026 byte for byte and
`routing_scores.csv` row for row (the same rows, 40 of them in another
order). Its generated markdown differs from them only by the recorded density
definition; its contract differs by that definition, by the code checksums
and by the hashes of the QL2 level's `null_cells.csv` and `null_delta.csv`,
which were rewritten on 17 November 2026 with the same rows in another order.
In the paper rebuild (`scripts/reproduce_paper_tables.sh`) the
analysis runs after the chance-agreement steps and after `core_density.R`,
and its outputs are compared with the archived copies. The archive staged on
5 October 2026 predates this analysis and holds none of its outputs, so it
must be staged again before a rebuild can compare them. The selection,
routing, banding and pooling helpers are in `scripts/density_routing_lib.R`,
tested by `tests/testthat/test-density-routing.R`.

## Bands

Densities are first returns per m² in the plot cores, and the level columns
are labelled by their five-site core medians. Stems sum the reference over a
band's cells: a stem counts once at every level whose cell falls in the band.
Ranges are rounded; a cell's band uses its unrounded density.

| Band | Pulses/m² | Scope | Cells | Plots | Stems | Median pulses/m² [range] | Cells at 9.8 | Cells at 4.4 | Cells at 2.2 | Cells at 1.8 | Cells at 1.1 | Cells at 0.6 |
| --- | --- | --- | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A (QL1 or denser) | ≥ 8 | five sites | 81 | 81 | 1,956 | 10.8 [8.08, 22.48] | 81 | 0 | 0 | 0 | 0 | 0 |
| B (QL2 to QL1) | 2 to < 8 | five sites | 244 | 106 | 5,548 | 3.8 [2.00, 7.96] | 25 | 106 | 86 | 27 | 0 | 0 |
| C (below QL2) | < 2 | five sites | 311 | 106 | 7,646 | 1.1 [0.39, 2.00] | 0 | 0 | 20 | 79 | 106 | 106 |
| A (QL1 or denser) | ≥ 8 | California | 35 | 35 | 567 | 12.1 [8.43, 22.48] | 35 | 0 | 0 | 0 | 0 | 0 |
| B (QL2 to QL1) | 2 to < 8 | California | 115 | 43 | 1,617 | 3.0 [2.05, 7.82] | 8 | 43 | 41 | 23 | 0 | 0 |
| C (below QL2) | < 2 | California | 108 | 43 | 1,788 | 1.1 [0.46, 1.98] | 0 | 0 | 2 | 20 | 43 | 43 |
| A (QL1 or denser) | ≥ 8 | Washington | 46 | 46 | 1,389 | 10.0 [8.08, 19.86] | 46 | 0 | 0 | 0 | 0 | 0 |
| B (QL2 to QL1) | 2 to < 8 | Washington | 129 | 63 | 3,931 | 4.0 [2.00, 7.96] | 17 | 63 | 45 | 4 | 0 | 0 |
| C (below QL2) | < 2 | Washington | 203 | 63 | 5,858 | 1.1 [0.39, 2.00] | 0 | 0 | 18 | 59 | 63 | 63 |

## Decision table and held-out check

The pick is the candidate with the highest pooled F1 on the band's California
cells, and the margin is its lead over the runner-up there. The Washington
best is chosen on the Washington cells themselves and is descriptive.
Corrected F1 is at the 4 m radius.

| Band | Route | Pick | California F1 | Runner-up (margin) | Washington F1 | Washington corrected F1 | Washington best | Its F1 | Pick minus best, F1 | Pick minus best, corrected F1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A | GPU | SegmentAnyTree | 0.456 [0.393, 0.518] | ForestFormer3D (+0.009) | 0.518 [0.484, 0.550] | 0.216 [0.189, 0.244] | SegmentAnyTree | 0.518 [0.484, 0.550] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| B | GPU | SegmentAnyTree | 0.433 [0.393, 0.475] | ForestFormer3D (+0.002) | 0.498 [0.470, 0.522] | 0.192 [0.164, 0.221] | SegmentAnyTree | 0.498 [0.470, 0.522] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| C | GPU | `multichm` | 0.424 [0.390, 0.460] | AMS3D (+0.030) | 0.450 [0.429, 0.472] | 0.129 [0.110, 0.150] | TreeisoNet | 0.476 [0.445, 0.504] | −0.026 [−0.057, +0.006] | −0.043 [−0.064, −0.021] |
| A | CPU | `multichm` | 0.425 [0.383, 0.472] | CHM-VWF (+0.063) | 0.454 [0.427, 0.480] | 0.133 [0.108, 0.160] | CHM-VWF | 0.489 [0.453, 0.525] | −0.035 [−0.062, −0.005] | −0.056 [−0.082, −0.030] |
| B | CPU | `multichm` | 0.424 [0.385, 0.465] | CHM-VWF (+0.056) | 0.459 [0.439, 0.480] | 0.149 [0.126, 0.173] | `ptrees` | 0.460 [0.428, 0.489] | −0.001 [−0.029, +0.029] | −0.016 [−0.041, +0.011] |
| C | CPU | `multichm` | 0.424 [0.390, 0.460] | AMS3D (+0.030) | 0.450 [0.429, 0.472] | 0.129 [0.110, 0.150] | AMS3D | 0.450 [0.425, 0.477] | −0.000 [−0.027, +0.026] | −0.022 [−0.041, −0.003] |

The choices made once for every density do not depend on the bands and are
unchanged:

| Choice | Candidates | Selected on | Pick | Its F1 | Runner-up (margin) |
| --- | --- | --- | --- | --- | --- |
| Native-only choice | GPU | California, native level | SegmentAnyTree | 0.461 | ForestFormer3D (+0.001) |
| Native-only choice | CPU | California, native level | `multichm` | 0.428 | CHM-VWF (+0.054) |
| Single choice | GPU | California, all cells | `multichm` | 0.424 | ForestFormer3D (+0.009) |
| Single choice | CPU | California, all cells | `multichm` | 0.424 | CHM-VWF (+0.063) |

## Every candidate by band

### California (selection data, in sample)

| Detector | Picked in | A: F1 | A: corrected F1 | B: F1 | B: corrected F1 | C: F1 | C: corrected F1 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ForestFormer3D |  | 0.447 [0.406, 0.493] | 0.255 [0.210, 0.309] | 0.431 [0.392, 0.475] | 0.257 [0.219, 0.305] | 0.390 [0.354, 0.428] | 0.214 [0.181, 0.251] |
| SegmentAnyTree | GPU AB | 0.456 [0.393, 0.518] | 0.265 [0.205, 0.334] | 0.433 [0.393, 0.475] | 0.263 [0.211, 0.315] | 0.279 [0.245, 0.313] | 0.152 [0.124, 0.182] |
| TreeisoNet |  | 0.361 [0.320, 0.406] | 0.190 [0.147, 0.243] | 0.364 [0.326, 0.406] | 0.202 [0.164, 0.246] | 0.369 [0.328, 0.411] | 0.199 [0.161, 0.241] |
| `multichm` | GPU C, CPU ABC | 0.425 [0.383, 0.472] | 0.230 [0.188, 0.280] | 0.424 [0.385, 0.465] | 0.235 [0.196, 0.277] | 0.424 [0.390, 0.460] | 0.220 [0.191, 0.255] |
| CHM-VWF |  | 0.362 [0.320, 0.403] | 0.195 [0.152, 0.244] | 0.368 [0.322, 0.416] | 0.233 [0.183, 0.290] | 0.353 [0.311, 0.394] | 0.213 [0.172, 0.259] |
| AMS3D |  | 0.206 [0.158, 0.271] | 0.077 [0.049, 0.116] | 0.317 [0.275, 0.362] | 0.152 [0.119, 0.190] | 0.393 [0.351, 0.438] | 0.197 [0.155, 0.245] |
| `ptrees` |  | 0.251 [0.206, 0.303] | 0.100 [0.067, 0.140] | 0.353 [0.314, 0.400] | 0.194 [0.155, 0.243] | 0.277 [0.244, 0.310] | 0.150 [0.124, 0.182] |
| `lmfauto` |  | 0.339 [0.291, 0.389] | 0.165 [0.117, 0.218] | 0.358 [0.312, 0.407] | 0.192 [0.149, 0.243] | 0.341 [0.296, 0.394] | 0.160 [0.118, 0.210] |

### Washington (held out)

| Detector | Picked in | A: F1 | A: corrected F1 | B: F1 | B: corrected F1 | C: F1 | C: corrected F1 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ForestFormer3D |  | 0.512 [0.486, 0.538] | 0.193 [0.164, 0.221] | 0.491 [0.469, 0.514] | 0.176 [0.153, 0.200] | 0.459 [0.436, 0.481] | 0.151 [0.126, 0.178] |
| SegmentAnyTree | GPU AB | 0.518 [0.484, 0.550] | 0.216 [0.189, 0.244] | 0.498 [0.470, 0.522] | 0.192 [0.164, 0.221] | 0.370 [0.346, 0.394] | 0.118 [0.098, 0.139] |
| TreeisoNet |  | 0.488 [0.455, 0.520] | 0.178 [0.150, 0.207] | 0.492 [0.461, 0.521] | 0.184 [0.157, 0.210] | 0.476 [0.445, 0.504] | 0.173 [0.144, 0.203] |
| `multichm` | GPU C, CPU ABC | 0.454 [0.427, 0.480] | 0.133 [0.108, 0.160] | 0.459 [0.439, 0.480] | 0.149 [0.126, 0.173] | 0.450 [0.429, 0.472] | 0.129 [0.110, 0.150] |
| CHM-VWF |  | 0.489 [0.453, 0.525] | 0.189 [0.153, 0.230] | 0.412 [0.383, 0.443] | 0.151 [0.124, 0.182] | 0.395 [0.368, 0.423] | 0.143 [0.118, 0.172] |
| AMS3D |  | 0.233 [0.202, 0.264] | 0.047 [0.036, 0.059] | 0.354 [0.327, 0.382] | 0.090 [0.073, 0.108] | 0.450 [0.425, 0.477] | 0.151 [0.128, 0.180] |
| `ptrees` |  | 0.349 [0.300, 0.402] | 0.088 [0.061, 0.121] | 0.460 [0.428, 0.489] | 0.165 [0.140, 0.192] | 0.376 [0.351, 0.400] | 0.136 [0.111, 0.162] |
| `lmfauto` |  | 0.418 [0.366, 0.473] | 0.134 [0.103, 0.172] | 0.294 [0.258, 0.337] | 0.074 [0.056, 0.097] | 0.255 [0.225, 0.294] | 0.057 [0.043, 0.077] |

### Five sites

| Detector | Picked in | A: F1 | A: corrected F1 | B: F1 | B: corrected F1 | C: F1 | C: corrected F1 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ForestFormer3D |  | 0.493 [0.470, 0.517] | 0.214 [0.189, 0.238] | 0.472 [0.453, 0.493] | 0.205 [0.184, 0.227] | 0.441 [0.422, 0.460] | 0.170 [0.149, 0.192] |
| SegmentAnyTree | GPU AB | 0.497 [0.466, 0.528] | 0.235 [0.206, 0.264] | 0.477 [0.454, 0.498] | 0.219 [0.193, 0.244] | 0.350 [0.328, 0.369] | 0.126 [0.110, 0.144] |
| TreeisoNet |  | 0.446 [0.416, 0.476] | 0.182 [0.156, 0.209] | 0.448 [0.421, 0.473] | 0.190 [0.167, 0.212] | 0.447 [0.420, 0.474] | 0.181 [0.157, 0.204] |
| `multichm` | GPU C, CPU ABC | 0.445 [0.422, 0.470] | 0.166 [0.144, 0.192] | 0.448 [0.430, 0.466] | 0.180 [0.160, 0.201] | 0.443 [0.426, 0.462] | 0.155 [0.139, 0.173] |
| CHM-VWF |  | 0.451 [0.419, 0.481] | 0.192 [0.164, 0.223] | 0.399 [0.373, 0.423] | 0.178 [0.152, 0.206] | 0.385 [0.361, 0.409] | 0.162 [0.140, 0.187] |
| AMS3D |  | 0.224 [0.194, 0.256] | 0.058 [0.046, 0.071] | 0.342 [0.318, 0.366] | 0.111 [0.095, 0.129] | 0.437 [0.414, 0.461] | 0.164 [0.143, 0.187] |
| `ptrees` |  | 0.316 [0.278, 0.355] | 0.092 [0.071, 0.118] | 0.427 [0.399, 0.451] | 0.175 [0.153, 0.199] | 0.352 [0.331, 0.373] | 0.140 [0.120, 0.160] |
| `lmfauto` |  | 0.398 [0.356, 0.437] | 0.143 [0.114, 0.174] | 0.307 [0.276, 0.343] | 0.099 [0.080, 0.124] | 0.269 [0.241, 0.305] | 0.074 [0.059, 0.094] |

## Washington: each pick against the other candidates of its band

Paired differences, pick minus candidate, in F1 and in corrected F1:

| Band | Route | Pick | Versus | Pick minus candidate, F1 | Pick minus candidate, corrected F1 |
| --- | --- | --- | --- | --- | --- |
| A | GPU | SegmentAnyTree | ForestFormer3D | +0.006 [−0.020, +0.027] | +0.023 [−0.001, +0.048] |
| A | GPU | SegmentAnyTree | TreeisoNet | +0.029 [+0.002, +0.054] | +0.038 [+0.008, +0.068] |
| A | GPU | SegmentAnyTree | `multichm` | +0.064 [+0.035, +0.087] | +0.083 [+0.058, +0.104] |
| A | GPU | SegmentAnyTree | CHM-VWF | +0.029 [+0.003, +0.054] | +0.026 [−0.008, +0.055] |
| A | GPU | SegmentAnyTree | AMS3D | +0.284 [+0.245, +0.317] | +0.168 [+0.141, +0.195] |
| A | GPU | SegmentAnyTree | `ptrees` | +0.169 [+0.118, +0.217] | +0.128 [+0.091, +0.162] |
| A | GPU | SegmentAnyTree | `lmfauto` | +0.099 [+0.034, +0.143] | +0.081 [+0.044, +0.109] |
| B | GPU | SegmentAnyTree | ForestFormer3D | +0.007 [−0.017, +0.026] | +0.017 [−0.007, +0.038] |
| B | GPU | SegmentAnyTree | TreeisoNet | +0.006 [−0.014, +0.027] | +0.009 [−0.015, +0.028] |
| B | GPU | SegmentAnyTree | `multichm` | +0.039 [+0.012, +0.062] | +0.044 [+0.016, +0.066] |
| B | GPU | SegmentAnyTree | CHM-VWF | +0.086 [+0.058, +0.110] | +0.041 [+0.015, +0.066] |
| B | GPU | SegmentAnyTree | AMS3D | +0.144 [+0.112, +0.171] | +0.102 [+0.077, +0.126] |
| B | GPU | SegmentAnyTree | `ptrees` | +0.038 [+0.016, +0.057] | +0.028 [+0.004, +0.048] |
| B | GPU | SegmentAnyTree | `lmfauto` | +0.204 [+0.154, +0.241] | +0.119 [+0.092, +0.143] |
| C | GPU | `multichm` | ForestFormer3D | −0.010 [−0.025, +0.006] | −0.022 [−0.037, −0.007] |
| C | GPU | `multichm` | SegmentAnyTree | +0.080 [+0.058, +0.103] | +0.012 [−0.006, +0.031] |
| C | GPU | `multichm` | TreeisoNet (Washington best) | −0.026 [−0.057, +0.006] | −0.043 [−0.064, −0.021] |
| C | GPU | `multichm` | CHM-VWF | +0.055 [+0.027, +0.082] | −0.014 [−0.036, +0.005] |
| C | GPU | `multichm` | AMS3D | −0.000 [−0.027, +0.026] | −0.022 [−0.041, −0.003] |
| C | GPU | `multichm` | `ptrees` | +0.074 [+0.047, +0.103] | −0.007 [−0.025, +0.012] |
| C | GPU | `multichm` | `lmfauto` | +0.195 [+0.156, +0.224] | +0.072 [+0.054, +0.088] |
| A | CPU | `multichm` | CHM-VWF (Washington best) | −0.035 [−0.062, −0.005] | −0.056 [−0.082, −0.030] |
| A | CPU | `multichm` | `lmfauto` | +0.035 [−0.019, +0.080] | −0.002 [−0.037, +0.027] |
| A | CPU | `multichm` | `ptrees` | +0.105 [+0.061, +0.149] | +0.045 [+0.008, +0.079] |
| A | CPU | `multichm` | AMS3D | +0.220 [+0.189, +0.252] | +0.086 [+0.061, +0.112] |
| B | CPU | `multichm` | CHM-VWF | +0.047 [+0.017, +0.080] | −0.002 [−0.028, +0.025] |
| B | CPU | `multichm` | `lmfauto` | +0.165 [+0.125, +0.201] | +0.075 [+0.054, +0.093] |
| B | CPU | `multichm` | `ptrees` (Washington best) | −0.001 [−0.029, +0.029] | −0.016 [−0.041, +0.011] |
| B | CPU | `multichm` | AMS3D | +0.105 [+0.079, +0.132] | +0.059 [+0.037, +0.081] |
| C | CPU | `multichm` | CHM-VWF | +0.055 [+0.027, +0.082] | −0.014 [−0.036, +0.005] |
| C | CPU | `multichm` | `lmfauto` | +0.195 [+0.156, +0.224] | +0.072 [+0.054, +0.088] |
| C | CPU | `multichm` | `ptrees` | +0.074 [+0.047, +0.103] | −0.007 [−0.025, +0.012] |
| C | CPU | `multichm` | AMS3D (Washington best) | −0.000 [−0.027, +0.026] | −0.022 [−0.041, −0.003] |

## Every cell pooled

Each policy pools its cells over the whole density series of a scope, so the
six levels weigh equally: a route runs its band's pick in each cell, and a
fixed detector runs in every cell.

| Policy or detector | Five sites, F1 | Five sites, corrected F1 | California, F1 | California, corrected F1 | Washington, F1 | Washington, corrected F1 |
| --- | --- | --- | --- | --- | --- | --- |
| GPU route | 0.463 [0.445, 0.481] | 0.189 [0.170, 0.209] | 0.432 [0.398, 0.471] | 0.245 [0.206, 0.289] | 0.475 [0.454, 0.496] | 0.162 [0.143, 0.184] |
| CPU route | 0.445 [0.428, 0.464] | 0.166 [0.150, 0.184] | 0.424 [0.389, 0.461] | 0.228 [0.195, 0.264] | 0.454 [0.434, 0.475] | 0.137 [0.119, 0.158] |
| Native-only choice, GPU | 0.428 [0.407, 0.447] | 0.180 [0.162, 0.199] | 0.388 [0.355, 0.424] | 0.224 [0.185, 0.267] | 0.444 [0.420, 0.465] | 0.159 [0.140, 0.182] |
| Native-only choice, CPU | 0.445 [0.428, 0.464] | 0.166 [0.150, 0.184] | 0.424 [0.389, 0.461] | 0.228 [0.195, 0.264] | 0.454 [0.434, 0.475] | 0.137 [0.119, 0.158] |
| Single choice, GPU | 0.445 [0.428, 0.464] | 0.166 [0.150, 0.184] | 0.424 [0.389, 0.461] | 0.228 [0.195, 0.264] | 0.454 [0.434, 0.475] | 0.137 [0.119, 0.158] |
| Single choice, CPU | 0.445 [0.428, 0.464] | 0.166 [0.150, 0.184] | 0.424 [0.389, 0.461] | 0.228 [0.195, 0.264] | 0.454 [0.434, 0.475] | 0.137 [0.119, 0.158] |
| Washington best per band, GPU (descriptive) | 0.466 [0.441, 0.489] | 0.203 [0.180, 0.224] | 0.409 [0.372, 0.449] | 0.235 [0.193, 0.283] | 0.489 [0.463, 0.514] | 0.185 [0.162, 0.211] |
| Washington best per band, CPU (descriptive) | 0.435 [0.412, 0.455] | 0.171 [0.151, 0.192] | 0.373 [0.339, 0.410] | 0.195 [0.159, 0.238] | 0.458 [0.434, 0.480] | 0.160 [0.138, 0.186] |
| ForestFormer3D | 0.460 [0.442, 0.477] | 0.189 [0.169, 0.209] | 0.415 [0.379, 0.453] | 0.237 [0.203, 0.278] | 0.478 [0.457, 0.498] | 0.166 [0.143, 0.189] |
| SegmentAnyTree | 0.428 [0.407, 0.447] | 0.180 [0.162, 0.199] | 0.388 [0.355, 0.424] | 0.224 [0.185, 0.267] | 0.444 [0.420, 0.465] | 0.159 [0.140, 0.182] |
| TreeisoNet | 0.447 [0.422, 0.472] | 0.185 [0.162, 0.206] | 0.366 [0.326, 0.405] | 0.199 [0.163, 0.241] | 0.483 [0.455, 0.510] | 0.177 [0.152, 0.204] |
| `multichm` | 0.445 [0.428, 0.464] | 0.166 [0.150, 0.184] | 0.424 [0.389, 0.461] | 0.228 [0.195, 0.264] | 0.454 [0.434, 0.475] | 0.137 [0.119, 0.158] |
| CHM-VWF | 0.401 [0.379, 0.423] | 0.172 [0.149, 0.195] | 0.361 [0.321, 0.402] | 0.218 [0.177, 0.263] | 0.415 [0.391, 0.442] | 0.152 [0.128, 0.181] |
| AMS3D | 0.346 [0.321, 0.369] | 0.113 [0.098, 0.129] | 0.308 [0.267, 0.354] | 0.143 [0.110, 0.178] | 0.362 [0.334, 0.389] | 0.099 [0.084, 0.117] |
| `ptrees` | 0.370 [0.348, 0.391] | 0.138 [0.122, 0.157] | 0.299 [0.268, 0.336] | 0.151 [0.122, 0.187] | 0.398 [0.375, 0.422] | 0.133 [0.114, 0.154] |
| `lmfauto` | 0.292 [0.265, 0.327] | 0.087 [0.071, 0.109] | 0.347 [0.304, 0.394] | 0.172 [0.130, 0.219] | 0.280 [0.249, 0.321] | 0.068 [0.052, 0.089] |

The GPU route minus each fixed detector and the other choices, every cell:

| Versus | Five sites, F1 | Five sites, corrected F1 | California, F1 | California, corrected F1 | Washington, F1 | Washington, corrected F1 |
| --- | --- | --- | --- | --- | --- | --- |
| ForestFormer3D | +0.003 [−0.006, +0.012] | +0.000 [−0.010, +0.010] | +0.017 [+0.002, +0.035] | +0.008 [−0.009, +0.027] | −0.003 [−0.014, +0.007] | −0.004 [−0.018, +0.008] |
| SegmentAnyTree | +0.035 [+0.026, +0.046] | +0.009 [+0.002, +0.017] | +0.045 [+0.031, +0.059] | +0.021 [+0.010, +0.033] | +0.031 [+0.019, +0.044] | +0.003 [−0.006, +0.012] |
| TreeisoNet | +0.016 [−0.002, +0.033] | +0.004 [−0.009, +0.019] | +0.067 [+0.039, +0.096] | +0.046 [+0.024, +0.071] | −0.008 [−0.029, +0.015] | −0.015 [−0.034, +0.002] |
| `multichm` | +0.018 [+0.009, +0.026] | +0.024 [+0.015, +0.032] | +0.008 [−0.005, +0.023] | +0.017 [−0.000, +0.036] | +0.022 [+0.010, +0.032] | +0.025 [+0.014, +0.034] |
| CHM-VWF | +0.062 [+0.042, +0.081] | +0.017 [−0.001, +0.034] | +0.072 [+0.032, +0.109] | +0.027 [−0.013, +0.065] | +0.060 [+0.035, +0.081] | +0.010 [−0.011, +0.026] |
| AMS3D | +0.117 [+0.097, +0.136] | +0.076 [+0.063, +0.089] | +0.124 [+0.095, +0.155] | +0.103 [+0.078, +0.130] | +0.113 [+0.090, +0.136] | +0.063 [+0.047, +0.078] |
| `ptrees` | +0.093 [+0.079, +0.107] | +0.051 [+0.040, +0.062] | +0.134 [+0.112, +0.155] | +0.094 [+0.075, +0.116] | +0.077 [+0.061, +0.092] | +0.029 [+0.016, +0.043] |
| `lmfauto` | +0.171 [+0.134, +0.201] | +0.102 [+0.083, +0.117] | +0.086 [+0.058, +0.112] | +0.073 [+0.049, +0.098] | +0.195 [+0.153, +0.227] | +0.094 [+0.075, +0.110] |
| Native-only choice, GPU | +0.035 [+0.026, +0.046] | +0.009 [+0.002, +0.017] | +0.045 [+0.031, +0.059] | +0.021 [+0.010, +0.033] | +0.031 [+0.019, +0.044] | +0.003 [−0.006, +0.012] |
| CPU route | +0.018 [+0.009, +0.026] | +0.024 [+0.015, +0.032] | +0.008 [−0.005, +0.023] | +0.017 [−0.000, +0.036] | +0.022 [+0.010, +0.032] | +0.025 [+0.014, +0.034] |
| Single choice, GPU | +0.018 [+0.009, +0.026] | +0.024 [+0.015, +0.032] | +0.008 [−0.005, +0.023] | +0.017 [−0.000, +0.036] | +0.022 [+0.010, +0.032] | +0.025 [+0.014, +0.034] |
| Washington best per band, GPU (descriptive) | −0.003 [−0.015, +0.010] | −0.013 [−0.022, −0.003] | +0.023 [+0.009, +0.039] | +0.010 [−0.004, +0.025] | −0.014 [−0.030, +0.002] | −0.023 [−0.035, −0.011] |

The CPU route minus each fixed detector and the other choices, every cell. The
CPU route, the CPU native-only choice and both single choices are `multichm`
in every band, so their rows are identical:

| Versus | Five sites, F1 | Five sites, corrected F1 | California, F1 | California, corrected F1 | Washington, F1 | Washington, corrected F1 |
| --- | --- | --- | --- | --- | --- | --- |
| ForestFormer3D | −0.015 [−0.025, −0.004] | −0.023 [−0.035, −0.012] | +0.009 [−0.004, +0.024] | −0.009 [−0.027, +0.009] | −0.025 [−0.037, −0.012] | −0.029 [−0.043, −0.015] |
| SegmentAnyTree | +0.017 [+0.001, +0.035] | −0.015 [−0.028, −0.001] | +0.037 [+0.013, +0.059] | +0.003 [−0.022, +0.028] | +0.010 [−0.011, +0.031] | −0.022 [−0.037, −0.007] |
| TreeisoNet | −0.002 [−0.023, +0.021] | −0.019 [−0.034, −0.001] | +0.059 [+0.031, +0.090] | +0.029 [+0.001, +0.057] | −0.030 [−0.056, −0.001] | −0.040 [−0.058, −0.022] |
| `multichm` | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| CHM-VWF | +0.045 [+0.022, +0.066] | −0.006 [−0.025, +0.012] | +0.063 [+0.023, +0.103] | +0.010 [−0.031, +0.051] | +0.038 [+0.013, +0.066] | −0.016 [−0.035, +0.003] |
| AMS3D | +0.099 [+0.079, +0.120] | +0.052 [+0.039, +0.067] | +0.116 [+0.082, +0.148] | +0.085 [+0.058, +0.113] | +0.092 [+0.069, +0.116] | +0.037 [+0.022, +0.054] |
| `ptrees` | +0.076 [+0.059, +0.092] | +0.027 [+0.015, +0.040] | +0.125 [+0.104, +0.146] | +0.077 [+0.057, +0.097] | +0.055 [+0.035, +0.075] | +0.004 [−0.011, +0.019] |
| `lmfauto` | +0.153 [+0.120, +0.181] | +0.078 [+0.060, +0.093] | +0.077 [+0.046, +0.105] | +0.056 [+0.027, +0.083] | +0.174 [+0.136, +0.205] | +0.069 [+0.052, +0.085] |
| Native-only choice, CPU | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| Single choice, CPU | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| Washington best per band, CPU (descriptive) | +0.010 [−0.007, +0.028] | −0.006 [−0.019, +0.008] | +0.052 [+0.035, +0.068] | +0.033 [+0.012, +0.054] | −0.004 [−0.025, +0.019] | −0.024 [−0.039, −0.006] |

The GPU native-only choice (SegmentAnyTree at every level) minus each fixed
detector, every cell; it does not depend on the bands:

| Versus | Five sites, F1 | Five sites, corrected F1 | California, F1 | California, corrected F1 | Washington, F1 | Washington, corrected F1 |
| --- | --- | --- | --- | --- | --- | --- |
| ForestFormer3D | −0.032 [−0.046, −0.019] | −0.009 [−0.021, +0.003] | −0.028 [−0.049, −0.004] | −0.013 [−0.034, +0.008] | −0.034 [−0.052, −0.019] | −0.006 [−0.022, +0.008] |
| SegmentAnyTree | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| TreeisoNet | −0.019 [−0.032, −0.006] | −0.004 [−0.017, +0.008] | +0.022 [−0.002, +0.047] | +0.025 [+0.005, +0.048] | −0.039 [−0.054, −0.025] | −0.018 [−0.034, −0.003] |
| `multichm` | −0.017 [−0.035, −0.001] | +0.015 [+0.001, +0.028] | −0.037 [−0.059, −0.013] | −0.003 [−0.028, +0.022] | −0.010 [−0.031, +0.011] | +0.022 [+0.007, +0.037] |
| CHM-VWF | +0.027 [+0.009, +0.043] | +0.008 [−0.010, +0.024] | +0.027 [−0.008, +0.059] | +0.007 [−0.029, +0.039] | +0.029 [+0.007, +0.046] | +0.007 [−0.014, +0.023] |
| AMS3D | +0.082 [+0.058, +0.103] | +0.067 [+0.053, +0.082] | +0.079 [+0.041, +0.116] | +0.082 [+0.053, +0.111] | +0.082 [+0.055, +0.108] | +0.060 [+0.042, +0.076] |
| `ptrees` | +0.058 [+0.043, +0.072] | +0.042 [+0.030, +0.054] | +0.089 [+0.069, +0.110] | +0.073 [+0.053, +0.094] | +0.046 [+0.028, +0.064] | +0.027 [+0.012, +0.042] |
| `lmfauto` | +0.136 [+0.094, +0.169] | +0.093 [+0.074, +0.109] | +0.041 [+0.012, +0.070] | +0.052 [+0.026, +0.077] | +0.164 [+0.115, +0.201] | +0.092 [+0.070, +0.108] |

## The native-only choice by band

The GPU route minus the GPU native-only choice in each band; bands A and B
run the same detector in both:

| Band | Compute | Native-only choice | Route's pick | Scope | Route minus native-only, F1 | Route minus native-only, corrected F1 |
| --- | --- | --- | --- | --- | --- | --- |
| A | GPU | SegmentAnyTree | SegmentAnyTree | five sites | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| A | GPU | SegmentAnyTree | SegmentAnyTree | California | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| A | GPU | SegmentAnyTree | SegmentAnyTree | Washington | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| B | GPU | SegmentAnyTree | SegmentAnyTree | five sites | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| B | GPU | SegmentAnyTree | SegmentAnyTree | California | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| B | GPU | SegmentAnyTree | SegmentAnyTree | Washington | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| C | GPU | SegmentAnyTree | `multichm` | five sites | +0.094 [+0.074, +0.116] | +0.029 [+0.014, +0.046] |
| C | GPU | SegmentAnyTree | `multichm` | California | +0.144 [+0.108, +0.181] | +0.069 [+0.041, +0.100] |
| C | GPU | SegmentAnyTree | `multichm` | Washington | +0.080 [+0.058, +0.103] | +0.012 [−0.006, +0.031] |

## Readings

- **What the routes pick.** With a GPU: SegmentAnyTree at QL2 density or
  denser (bands A and B) and `multichm` below QL2. With only a CPU:
  `multichm` in every band, so the CPU route is a single detector. The
  California margins behind the GPU picks at QL2 density and above are small,
  and neither pick separates from its runner-up on the development data:
  SegmentAnyTree minus ForestFormer3D is +0.009 [−0.028, +0.043] F1 in band A
  and +0.002 [−0.024, +0.031] in band B, and `multichm` is level with the
  pick too (the pick minus `multichm` is +0.030 [−0.010, +0.070] and +0.008
  [−0.018, +0.037]). The band-B pick also changes with the density
  definition (see below). Below QL2, `multichm` leads AMS3D by +0.030
  [+0.003, +0.057] F1, narrowly, and by +0.023 [−0.012, +0.057] in
  corrected F1, which includes zero. The CPU pick leads CHM-VWF by +0.063
  [+0.033, +0.093] F1 in band A and, narrowly, by +0.056 [+0.003, +0.108]
  in band B; in corrected F1 neither lead excludes zero (+0.035 [−0.007,
  +0.071] and +0.003 [−0.053, +0.054]).
- **How far the picks are from the Washington best.** With a GPU, the band-A
  and band-B picks are also the Washington best, at 0.518 [0.484, 0.550] and
  0.498 [0.470, 0.522]. In band C, `multichm` (0.450 [0.429, 0.472]) minus
  TreeisoNet (0.476 [0.445, 0.504]) is −0.026 [−0.057, +0.006]. For the CPU
  route, `multichm` minus the Washington best is, narrowly, −0.035 [−0.062,
  −0.005] in band A (CHM-VWF), −0.001 [−0.029, +0.029] in band B (`ptrees`)
  and −0.000 [−0.027, +0.026] in band C (AMS3D). In corrected F1 three gaps
  exclude zero: below QL2, `multichm` minus TreeisoNet is −0.043 [−0.064,
  −0.021] and, narrowly, minus AMS3D −0.022 [−0.041, −0.003], and in band A
  `multichm` minus CHM-VWF is −0.056 [−0.082, −0.030]. Over every Washington
  cell, the GPU route minus the per-band Washington best is −0.014 [−0.030,
  +0.002] in F1 and −0.023 [−0.035, −0.011] in corrected F1; for the CPU
  route the two are −0.004 [−0.025, +0.019] and, narrowly, −0.024 [−0.039,
  −0.006]. The Washington bests are chosen on the same data, so these gaps
  overstate what a choice made without the Washington data could recover.
- **What the native-only choice loses below the QL2 floor.** The GPU
  native-only choice is SegmentAnyTree, which won the native-level comparison
  in California by 0.001 F1 over ForestFormer3D. The route runs it at QL2
  density and above as well, so the two differ only below the floor. There
  (band C), the route's `multichm` minus SegmentAnyTree is +0.080 [+0.058,
  +0.103] F1 in Washington and +0.144 [+0.108, +0.181] in California. In
  corrected F1 it is +0.069 [+0.041, +0.100] in California, but +0.012
  [−0.006, +0.031] in Washington, which includes zero. Over every cell the
  route gains +0.031 [+0.019, +0.044] F1 in Washington and +0.003 [−0.006,
  +0.012] in corrected F1. Had the native-level choice fallen to
  ForestFormer3D, its row in the tables shows what that choice gives.
- **Whether one robust detector does as well as the routes.** ForestFormer3D
  at every level is level with the GPU route: the route minus ForestFormer3D
  is +0.003 [−0.006, +0.012] F1 on the five sites and −0.003 [−0.014, +0.007]
  in Washington, and in corrected F1 +0.000 [−0.010, +0.010] and −0.004
  [−0.018, +0.008]. TreeisoNet at every level is level with the route in
  Washington (−0.008 [−0.029, +0.015] F1 and −0.015 [−0.034, +0.002]
  corrected F1), but behind it in California (+0.067 [+0.039, +0.096]). Both
  were singled out after seeing the density series. Chosen by the routes' own
  rule on the California cells, the single choice is `multichm`, by 0.009 F1
  over ForestFormer3D, and the GPU route leads it in Washington by +0.022
  [+0.010, +0.032] F1 and +0.025 [+0.014, +0.034] corrected F1.
- **What routing adds and what it does not.** Routing by measured density
  avoids the one detector that collapses below the QL2 floor, a decision the
  ranking at native density cannot make: in California, SegmentAnyTree and
  ForestFormer3D are 0.001 F1 apart at native density. Below the floor the
  gain is clear in observed F1 in both regions, and in corrected F1 in
  California only. Routing adds no accuracy over the best single learned
  detector: with a GPU, ForestFormer3D at every density does as well as the
  route, and with only a CPU the route is `multichm` throughout. In
  Washington the GPU picks at QL2 density and above are the Washington best.
  The gaps to the Washington best that exclude zero are below the floor,
  where `multichm` registers to the mapped stems less well than TreeisoNet
  and, narrowly, AMS3D (corrected F1), and the CPU pick at QL1 density or
  denser, behind CHM-VWF (narrowly in F1, clearly in corrected F1).

## Change of density definition

The analysis first banded each cell by the clip manifest's first-return
density, measured over the whole evaluation clip: the plot core plus a 25 m
buffer. An internal review found that the thinning leaves the clip's edge
denser than its interior, so the whole-clip figure overstates the density of
the scored core by about 10% at every thinned level
([core density](core-density-results.md)). The bands now use the core's
density. The selection rule, candidates, counts and resamples are unchanged,
every detector's per-level scores are the same, and the check against the
master tables passes in both definitions; only the assignment of cells to
bands changes, and with it the band scores, the picks and the routes. The
whole-clip banding is kept as a sensitivity run (`DENSITY=clip`, under
`work/paper_runs/density_routing_clip/`), which reproduces the outputs of
22 October 2026.

**Cells.** 55 of the 636 cells change band, 53 of them downward: 26 cells of
the QL2 level and 19 of the level thinned to 4 points/m² move from band B to
C, and 8 native cells from A to B; one QL2-level cell moves from C to B and
one native cell from B to A.

| Scope | Band A, whole clip → core | Band B, whole clip → core | Band C, whole clip → core |
| --- | --- | --- | --- |
| five sites | 88 → 81 | 281 → 244 | 267 → 311 |
| California | 37 → 35 | 132 → 115 | 89 → 108 |
| Washington | 51 → 46 | 149 → 129 | 178 → 203 |

**Picks.** One pick changes: with a GPU, band B goes from ForestFormer3D to
SegmentAnyTree. On the whole-clip bands, ForestFormer3D led `multichm` by
0.0015 F1 and SegmentAnyTree by 0.011 (+0.011 [−0.015, +0.033]); on the core
bands, SegmentAnyTree leads ForestFormer3D by 0.0016. Neither definition
separates the band-B candidates, so the pick follows which cells fall in the
band rather than a difference the development data resolve. The California
leads of the picks over their runners-up, as paired F1 differences:

| Band | Compute | Whole clip: pick over runner-up | Core: pick over runner-up |
| --- | --- | --- | --- |
| A | GPU | SegmentAnyTree over ForestFormer3D, +0.008 [−0.028, +0.039] | SegmentAnyTree over ForestFormer3D, +0.009 [−0.028, +0.043] |
| B | GPU | ForestFormer3D over `multichm`, +0.001 [−0.018, +0.021] | SegmentAnyTree over ForestFormer3D, +0.002 [−0.024, +0.031] |
| C | GPU | `multichm` over AMS3D, +0.025 [−0.006, +0.055] | `multichm` over AMS3D, +0.030 [+0.003, +0.057] |
| A | CPU | `multichm` over CHM-VWF, +0.059 [+0.030, +0.088] | `multichm` over CHM-VWF, +0.063 [+0.033, +0.093] |
| B | CPU | `multichm` over CHM-VWF, +0.067 [+0.015, +0.117] | `multichm` over CHM-VWF, +0.056 [+0.003, +0.108] |
| C | CPU | `multichm` over AMS3D, +0.025 [−0.006, +0.055] | `multichm` over AMS3D, +0.030 [+0.003, +0.057] |

With core bands, the band-C lead of `multichm` over AMS3D excludes zero,
narrowly, where it did not before; the CPU band-B lead narrows to a
narrow one. The GPU picks in bands A and B separate from their runners-up
in neither definition.

**Held-out check.** Each pick minus the Washington best of its band, in F1
and corrected F1:

| Band | Compute | Whole clip | Core |
| --- | --- | --- | --- |
| A | GPU | the pick is the best (SegmentAnyTree, 0.512 [0.476, 0.546]) | the pick is the best (SegmentAnyTree, 0.518 [0.484, 0.550]) |
| B | GPU | ForestFormer3D minus SegmentAnyTree: −0.013 [−0.031, +0.010]; −0.024 [−0.046, +0.001] | the pick is the best (SegmentAnyTree, 0.498 [0.470, 0.522]) |
| C | GPU | `multichm` minus TreeisoNet: −0.024 [−0.055, +0.009]; −0.042 [−0.064, −0.018] | `multichm` minus TreeisoNet: −0.026 [−0.057, +0.006]; −0.043 [−0.064, −0.021] |
| A | CPU | `multichm` minus CHM-VWF: −0.028 [−0.057, +0.001]; −0.047 [−0.073, −0.022] | `multichm` minus CHM-VWF: −0.035 [−0.062, −0.005]; −0.056 [−0.082, −0.030] |
| B | CPU | the pick is the best (`multichm`, 0.461 [0.441, 0.483]) | `multichm` minus `ptrees`: −0.001 [−0.029, +0.029]; −0.016 [−0.041, +0.011] |
| C | CPU | `multichm` minus AMS3D: −0.009 [−0.033, +0.017]; −0.027 [−0.047, −0.009] | `multichm` minus AMS3D: −0.000 [−0.027, +0.026]; −0.022 [−0.041, −0.003] |
| Every cell | GPU | route minus per-band best: −0.016 [−0.036, +0.004]; −0.029 [−0.045, −0.014] | route minus per-band best: −0.014 [−0.030, +0.002]; −0.023 [−0.035, −0.011] |
| Every cell | CPU | route minus per-band best: −0.008 [−0.022, +0.006]; −0.019 [−0.029, −0.009] | route minus per-band best: −0.004 [−0.025, +0.019]; −0.024 [−0.039, −0.006] |

**Route-level comparisons**, every cell unless a band is named, F1 and
corrected F1:

| Comparison | Scope | Whole clip | Core |
| --- | --- | --- | --- |
| GPU route minus native-only choice, band C | Washington | +0.101 [+0.077, +0.126]; +0.024 [+0.006, +0.041] | +0.080 [+0.058, +0.103]; +0.012 [−0.006, +0.031] |
| GPU route minus native-only choice, band C | California | +0.173 [+0.128, +0.214]; +0.078 [+0.044, +0.114] | +0.144 [+0.108, +0.181]; +0.069 [+0.041, +0.100] |
| GPU route minus native-only choice, band B | Washington | −0.013 [−0.031, +0.010]; −0.024 [−0.046, +0.001] | the same detector |
| GPU route minus native-only choice | Washington | +0.029 [+0.013, +0.047]; −0.002 [−0.014, +0.011] | +0.031 [+0.019, +0.044]; +0.003 [−0.006, +0.012] |
| GPU route minus native-only choice | California | +0.043 [+0.024, +0.062]; +0.020 [+0.001, +0.037] | +0.045 [+0.031, +0.059]; +0.021 [+0.010, +0.033] |
| GPU route minus ForestFormer3D | five sites | +0.001 [−0.004, +0.007]; −0.004 [−0.010, +0.003] | +0.003 [−0.006, +0.012]; +0.000 [−0.010, +0.010] |
| GPU route minus ForestFormer3D | Washington | −0.005 [−0.012, +0.002]; −0.008 [−0.017, −0.000] | −0.003 [−0.014, +0.007]; −0.004 [−0.018, +0.008] |
| GPU route minus ForestFormer3D | California | +0.016 [+0.007, +0.025]; +0.007 [−0.003, +0.017] | +0.017 [+0.002, +0.035]; +0.008 [−0.009, +0.027] |
| GPU route minus TreeisoNet | Washington | −0.010 [−0.033, +0.015]; −0.020 [−0.039, −0.002] | −0.008 [−0.029, +0.015]; −0.015 [−0.034, +0.002] |
| GPU route minus single choice (`multichm`) | Washington | +0.020 [+0.012, +0.027]; +0.021 [+0.012, +0.029] | +0.022 [+0.010, +0.032]; +0.025 [+0.014, +0.034] |
| GPU route minus single choice (`multichm`) | California | +0.007 [−0.005, +0.019]; +0.016 [+0.001, +0.032] | +0.008 [−0.005, +0.023]; +0.017 [−0.000, +0.036] |
| GPU route, score | Washington | 0.473 [0.453, 0.494]; 0.157 [0.138, 0.179] | 0.475 [0.454, 0.496]; 0.162 [0.143, 0.184] |
| GPU route, score | five sites | 0.461 [0.444, 0.480]; 0.185 [0.167, 0.205] | 0.463 [0.445, 0.481]; 0.189 [0.170, 0.209] |

What the change does to the readings:

- **Below the QL2 floor in Washington**, the route's corrected-F1 gain over
  the native-only choice no longer excludes zero (+0.012 [−0.006, +0.031];
  it was +0.024 [+0.006, +0.041], narrowly). Its observed-F1 gain stays
  clear (+0.080 [+0.058, +0.103]). Band C now also holds the cells just
  below 2 pulses/m² in the cores, where SegmentAnyTree scores better than at
  the sparser levels: its Washington band-C F1 rises from 0.346 [0.323,
  0.370] to 0.370 [0.346, 0.394].
- **Above the floor**, the GPU route and the native-only choice now run the
  same detector. The earlier band-B difference between them in Washington
  (−0.013 [−0.031, +0.010] F1 and −0.024 [−0.046, +0.001] corrected F1, both
  including zero) no longer arises.
- **Against single detectors**, the narrow corrected-F1 leads of
  ForestFormer3D (−0.008 [−0.017, −0.000]) and TreeisoNet (−0.020 [−0.039,
  −0.002]) over the route in Washington are gone; both are level with it.
  The route's corrected-F1 lead over the single choice in California no
  longer excludes zero (its lower bound is −0.0004).
- **Unchanged**: routing avoids SegmentAnyTree's collapse below the QL2
  floor; it adds no accuracy over ForestFormer3D at every level; the CPU
  route is `multichm` in every band; and no GPU pick at QL2 density or above
  separates from its runner-up.

## Caveats

- **Post hoc.** The design was fixed after the five-site results were known, and
  the density definition was changed after the whole-clip picks were known; only
  the selection of the picks is blind to Washington.
- **A small development region.** California holds 43 of the 106 plots and 662
  of the 2,525 stems. The margins of the band-A and band-B GPU picks lie inside
  their intervals, and the band-C pick's lead excludes zero only narrowly, so
  another development sample could pick differently. The band-B pick already
  changes with the density definition.
- **Development-region tuning.** The detector settings were fixed on California
  data, so California scores are in sample for the settings as well as for the
  selection.
- **Decimation.** Every cell below native density is a decimated copy of the
  native cloud, so band C holds decimated cells only. The comparison with native
  sparse flights suggests that decimation is optimistic, mildly for four
  detectors and strongly for SegmentAnyTree's recall, and no native acquisition
  at or below QL2 density covers the plots. Band C's picks and the native-only
  choice's loss there are measured on simulated sparse clouds.
- **The baseline's smoothing.** CHM-VWF runs with its pre-declared smoothing
  rule below 8 pulses/m², which costs it 0.06 to 0.07 F1 on each of the five
  decimated levels ([baseline smoothing
  sensitivity](baseline-smoothing-sensitivity-results.md)). Its band-B and
  band-C scores, and the CPU route's choice against it, are those of the
  smoothed configuration. The run without the rule is a post hoc sensitivity
  configuration, not a benchmark arm, and is not a candidate. Level by level,
  `multichm` leads it in California by 0.04 to 0.05 F1 on every decimated level
  and in Washington is 0.02 to 0.04 F1 behind it, with intervals that include
  zero on three of the five levels in F1 and exclude it on all five in corrected
  F1 (−0.043 to −0.066). The Washington check of the CPU picks in bands B and C
  is therefore a check against the declared arms only. The detectors' density
  gates, this rule among them, read the whole-clip density of the runs: 8 native
  cells with a core below 8 pulses/m² ran on the branch for 8 or more, and 1 the
  reverse ([core density](core-density-results.md)).
- **Chance agreement.** Corrected F1 measures how much closer the detections
  lie to the mapped stems than shifted copies of the same detections. In
  [simulation](chance-correction-simulation-results.md) it understates skill in
  unclustered stands, and in clustered ones detections lying beside mapped
  stems rather than on them raise it without any skill, so corrected scores
  and their differences are not bounds on skill.
- **Reference completeness.** Every score uses the nominal plot core, whose
  precision counts unmapped trees as errors and is a lower bound; the
  censused-subplot scores are not routed here.
- **Weighting.** The every-cell scores weigh the six levels of the density
  series equally, each stem counting once per level: band C holds 311 cells,
  band B 244 and band A 81. A national archive has another mix of densities, and
  its pooled score would weigh the bands differently.
- **Scope.** The sites are western U.S. conifer forest and oak woodland, and the
  reference is live mapped stems of at least 10 cm DBH; the picks are not tested
  in broadleaf or deciduous forest.

## Outputs

Under `work/paper_runs/density_routing/` (core-density bands):

- `routing_cells.csv`: one row per cell with its whole-clip densities from
  the clip manifest (`pdens`, `frdens`), its core densities (`core_pdens`,
  `core_frdens`), its band and level label (both from the core density) and
  each policy's detector.
- `routing_bands.csv`: cells, plots, stems and core density per band and
  scope, with the cells of each level, the density definition and the
  band's median whole-clip density.
- `routing_picks.csv`: per route and band, the pick and runner-up with their
  California F1, the pick's Washington and five-site scores, the Washington
  best and the pick's paired difference to it.
- `routing_scores.csv`: per scope, every detector and policy in every band,
  over every cell and at every level: recall, precision, F1, null F1 and
  corrected F1 with intervals and pooled counts. `n_plots` counts the plots
  with a cell in the slice. `n_ref` (reference stems), `n_det` (detections in
  the plot core) and `TP` (matched stems) sum the observed counts of the
  slice's cells, except on the null F1 rows, which sum each cell's mean counts
  over the 200 shifts.
- `routing_contrasts.csv`: per scope and band, and over every cell, each
  policy minus each fixed detector and the other policies, in F1 and corrected
  F1 with paired intervals; rows against a Washington best are flagged
  descriptive.
- `routing_check.csv`: per detector, level and scope, F1 and corrected F1
  beside the master-table and chance-agreement values they must equal.
- `density_routing.md`: the tables above; `routing_contract.json`: the
  design, the density definition and the level medians, the picks, the
  hashes of the inputs (the core-density table among them) and the
  checksums of the code.

`work/paper_runs/density_routing_clip/` holds the same files for the whole-clip
bands, without the core columns; the outputs of 22 October 2026 are kept
unchanged in `work/paper_runs/density_routing.2026-11-17-clip-density/`.
