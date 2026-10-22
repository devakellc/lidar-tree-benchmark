# Density-routed detection pipeline

Checked on 22 October 2026 on the fixed evaluation clips of the five-site
`adopted` population (106 plots, 2,525 stems), at the six density levels of
the paper: native density, with a median of 9.8 first-return pulses/m², and
thinned levels with medians of 4.7, 2.5, 2.0, 1.3 and 0.6 pulses/m². The 2.0
level sits at the U.S. Geological Survey quality level 2 (QL2) floor and is
frozen in its own root. The analysis asks which detector a user of
national-mapping airborne LiDAR should run on a tile, given its measured
density and whether a GPU is available, and checks the answer on the
replication region.

**Post hoc.** The analysis was designed after the five-site results were
known: the bands, the candidate sets, the selection rule and the comparisons
were chosen with the density and regional results in view. The picks are made
on the California (development) cells only and checked on Washington
(replication), but the design itself is not blind to Washington. No detector
is re-run; the analysis re-pools the per-plot counts of the chance-agreement
re-score of the paper runs.

## Design

- **Bands.** Each cell, one plot at one density level, falls in a band of its
  measured first-return density, as a user would route a tile: A at 8
  pulses/m² or more (QL1 or denser), B from 2 to below 8 (QL2 to QL1), and C
  below 2 (below QL2). The QL1 and QL2 floors are the aggregate nominal pulse
  densities of 8 and 2 pulses/m². Routing is per cell, so the cells of one
  level can fall in two bands: at the QL2 level, 52 cells are in band B and 54
  in band C.
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
  marginal.
- **Check.** Before it writes its tables, the script recomputes every
  candidate's F1 at every level for the five sites, California and
  Washington, and stops unless the estimate and both interval bounds equal the
  master tables to 1e-9; it checks corrected F1 the same way against the
  chance-agreement re-score. All 144 rows agree.

## Regenerate

```sh
CLAUDE_JOB_DIR=$(pwd)/work/paper_runs Rscript scripts/paper_density_routing.R
# -> work/paper_runs/density_routing/: routing_{cells,bands,picks,scores,
#    contrasts,check}.csv, density_routing.md, routing_contract.json
```

The script reads `sensitivity/null_cells.csv` and `sensitivity/null_delta.csv`
of the job directory and of the QL2 level's job directory beside it
(`paper_runs_ql2`), the clip manifests and population of the two sealed roots,
and the master tables. `RUNG_JOBS=<job dir>:<root>` locates the QL2 level
elsewhere, as for `master_tables.R`. `scripts/reproduce_paper_tables.sh` runs
it after the chance-agreement steps and compares its outputs with the archived
copies. The selection, routing and pooling helpers are in
`scripts/density_routing_lib.R`, tested by
`tests/testthat/test-density-routing.R`.

## Bands

Stems sum the reference over a band's cells: a stem counts once at every level
whose cell falls in the band. Ranges are rounded; a cell's band uses its
unrounded density.

| Band | Pulses/m² | Scope | Cells | Plots | Stems | Median pulses/m² [range] | Cells at 9.8 | Cells at 4.7 | Cells at 2.5 | Cells at 2.0 | Cells at 1.3 | Cells at 0.6 |
| --- | --- | --- | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A (QL1 or denser) | ≥ 8 | five sites | 88 | 88 | 2,175 | 10.5 [8.09, 17.76] | 88 | 0 | 0 | 0 | 0 | 0 |
| B (QL2 to QL1) | 2 to < 8 | five sites | 281 | 106 | 6,403 | 3.1 [2.01, 7.98] | 18 | 106 | 105 | 52 | 0 | 0 |
| C (below QL2) | < 2 | five sites | 267 | 106 | 6,572 | 1.2 [0.53, 2.00] | 0 | 0 | 1 | 54 | 106 | 106 |
| A (QL1 or denser) | ≥ 8 | California | 37 | 37 | 603 | 12.2 [8.51, 17.76] | 37 | 0 | 0 | 0 | 0 | 0 |
| B (QL2 to QL1) | 2 to < 8 | California | 132 | 43 | 2,017 | 3.1 [2.01, 7.98] | 6 | 43 | 43 | 40 | 0 | 0 |
| C (below QL2) | < 2 | California | 89 | 43 | 1,352 | 1.2 [0.62, 1.99] | 0 | 0 | 0 | 3 | 43 | 43 |
| A (QL1 or denser) | ≥ 8 | Washington | 51 | 51 | 1,572 | 9.6 [8.09, 15.16] | 51 | 0 | 0 | 0 | 0 | 0 |
| B (QL2 to QL1) | 2 to < 8 | Washington | 149 | 63 | 4,386 | 3.9 [2.03, 7.67] | 12 | 63 | 62 | 12 | 0 | 0 |
| C (below QL2) | < 2 | Washington | 178 | 63 | 5,220 | 1.2 [0.53, 2.00] | 0 | 0 | 1 | 51 | 63 | 63 |

## Decision table and held-out check

The pick is the candidate with the highest pooled F1 on the band's California
cells, and the margin is its lead over the runner-up there. The Washington
best is chosen on the Washington cells themselves and is descriptive.
Corrected F1 is at the 4 m radius.

| Band | Route | Pick | California F1 | Runner-up (margin) | Washington F1 | Washington corrected F1 | Washington best | Its F1 | Pick minus best, F1 | Pick minus best, corrected F1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A | GPU | SegmentAnyTree | 0.462 [0.404, 0.521] | ForestFormer3D (+0.008) | 0.512 [0.476, 0.546] | 0.208 [0.177, 0.238] | SegmentAnyTree | 0.512 [0.476, 0.546] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| B | GPU | ForestFormer3D | 0.428 [0.392, 0.469] | `multichm` (+0.001) | 0.489 [0.468, 0.512] | 0.169 [0.145, 0.196] | SegmentAnyTree | 0.502 [0.476, 0.526] | −0.013 [−0.031, +0.010] | −0.024 [−0.046, +0.001] |
| C | GPU | `multichm` | 0.419 [0.386, 0.454] | AMS3D (+0.025) | 0.448 [0.428, 0.470] | 0.133 [0.113, 0.153] | TreeisoNet | 0.471 [0.441, 0.501] | −0.024 [−0.055, +0.009] | −0.042 [−0.064, −0.018] |
| A | CPU | `multichm` | 0.428 [0.388, 0.472] | CHM-VWF (+0.059) | 0.454 [0.428, 0.478] | 0.135 [0.111, 0.161] | CHM-VWF | 0.482 [0.446, 0.520] | −0.028 [−0.057, +0.001] | −0.047 [−0.073, −0.022] |
| B | CPU | `multichm` | 0.426 [0.388, 0.466] | CHM-VWF (+0.067) | 0.461 [0.441, 0.483] | 0.142 [0.120, 0.166] | `multichm` | 0.461 [0.441, 0.483] | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| C | CPU | `multichm` | 0.419 [0.386, 0.454] | AMS3D (+0.025) | 0.448 [0.428, 0.470] | 0.133 [0.113, 0.153] | AMS3D | 0.456 [0.432, 0.482] | −0.009 [−0.033, +0.017] | −0.027 [−0.047, −0.009] |

The choices made once for every density:

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
| ForestFormer3D | GPU B | 0.454 [0.414, 0.499] | 0.264 [0.220, 0.316] | 0.428 [0.392, 0.469] | 0.247 [0.210, 0.292] | 0.380 [0.338, 0.420] | 0.213 [0.180, 0.250] |
| SegmentAnyTree | GPU A | 0.462 [0.404, 0.521] | 0.273 [0.214, 0.339] | 0.417 [0.379, 0.460] | 0.244 [0.196, 0.296] | 0.246 [0.207, 0.283] | 0.147 [0.113, 0.181] |
| TreeisoNet |  | 0.363 [0.323, 0.407] | 0.193 [0.151, 0.244] | 0.363 [0.323, 0.403] | 0.197 [0.159, 0.240] | 0.371 [0.330, 0.414] | 0.206 [0.171, 0.247] |
| `multichm` | GPU C, CPU ABC | 0.428 [0.388, 0.472] | 0.232 [0.190, 0.278] | 0.426 [0.388, 0.466] | 0.229 [0.192, 0.271] | 0.419 [0.386, 0.454] | 0.225 [0.195, 0.259] |
| CHM-VWF |  | 0.369 [0.329, 0.410] | 0.203 [0.159, 0.251] | 0.360 [0.317, 0.405] | 0.222 [0.175, 0.273] | 0.357 [0.313, 0.399] | 0.220 [0.178, 0.266] |
| AMS3D |  | 0.213 [0.163, 0.279] | 0.082 [0.052, 0.123] | 0.325 [0.282, 0.370] | 0.151 [0.118, 0.189] | 0.394 [0.355, 0.436] | 0.211 [0.170, 0.258] |
| `ptrees` |  | 0.256 [0.211, 0.307] | 0.104 [0.072, 0.144] | 0.345 [0.307, 0.386] | 0.186 [0.147, 0.232] | 0.266 [0.235, 0.300] | 0.151 [0.124, 0.181] |
| `lmfauto` |  | 0.346 [0.299, 0.393] | 0.173 [0.124, 0.227] | 0.359 [0.318, 0.406] | 0.186 [0.144, 0.234] | 0.335 [0.287, 0.389] | 0.158 [0.117, 0.207] |

### Washington (held out)

| Detector | Picked in | A: F1 | A: corrected F1 | B: F1 | B: corrected F1 | C: F1 | C: corrected F1 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ForestFormer3D | GPU B | 0.509 [0.483, 0.536] | 0.189 [0.160, 0.218] | 0.489 [0.468, 0.512] | 0.169 [0.145, 0.196] | 0.457 [0.437, 0.478] | 0.155 [0.130, 0.181] |
| SegmentAnyTree | GPU A | 0.512 [0.476, 0.546] | 0.208 [0.177, 0.238] | 0.502 [0.476, 0.526] | 0.193 [0.168, 0.222] | 0.346 [0.323, 0.370] | 0.109 [0.090, 0.130] |
| TreeisoNet |  | 0.483 [0.451, 0.514] | 0.173 [0.144, 0.203] | 0.496 [0.466, 0.521] | 0.182 [0.154, 0.210] | 0.471 [0.441, 0.501] | 0.175 [0.146, 0.204] |
| `multichm` | GPU C, CPU ABC | 0.454 [0.428, 0.478] | 0.135 [0.111, 0.161] | 0.461 [0.441, 0.483] | 0.142 [0.120, 0.166] | 0.448 [0.428, 0.470] | 0.133 [0.113, 0.153] |
| CHM-VWF |  | 0.482 [0.446, 0.520] | 0.182 [0.148, 0.220] | 0.415 [0.386, 0.446] | 0.152 [0.127, 0.183] | 0.390 [0.365, 0.417] | 0.143 [0.118, 0.171] |
| AMS3D |  | 0.241 [0.212, 0.272] | 0.049 [0.038, 0.062] | 0.361 [0.332, 0.390] | 0.091 [0.073, 0.109] | 0.456 [0.432, 0.482] | 0.160 [0.136, 0.189] |
| `ptrees` |  | 0.353 [0.308, 0.403] | 0.091 [0.064, 0.123] | 0.459 [0.430, 0.485] | 0.161 [0.139, 0.188] | 0.366 [0.343, 0.391] | 0.136 [0.110, 0.162] |
| `lmfauto` |  | 0.410 [0.360, 0.460] | 0.128 [0.100, 0.161] | 0.282 [0.247, 0.325] | 0.068 [0.051, 0.092] | 0.258 [0.227, 0.298] | 0.059 [0.045, 0.078] |

### Five sites

| Detector | Picked in | A: F1 | A: corrected F1 | B: F1 | B: corrected F1 | C: F1 | C: corrected F1 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ForestFormer3D | GPU B | 0.494 [0.471, 0.518] | 0.214 [0.189, 0.237] | 0.469 [0.450, 0.489] | 0.198 [0.176, 0.222] | 0.438 [0.420, 0.456] | 0.171 [0.150, 0.192] |
| SegmentAnyTree | GPU A | 0.496 [0.465, 0.527] | 0.233 [0.202, 0.263] | 0.473 [0.449, 0.495] | 0.212 [0.187, 0.238] | 0.327 [0.305, 0.347] | 0.117 [0.101, 0.135] |
| TreeisoNet |  | 0.445 [0.415, 0.472] | 0.180 [0.155, 0.204] | 0.448 [0.422, 0.473] | 0.187 [0.163, 0.211] | 0.447 [0.420, 0.474] | 0.184 [0.160, 0.206] |
| `multichm` | GPU C, CPU ABC | 0.446 [0.424, 0.467] | 0.168 [0.146, 0.191] | 0.449 [0.431, 0.469] | 0.175 [0.155, 0.197] | 0.441 [0.423, 0.459] | 0.156 [0.140, 0.174] |
| CHM-VWF |  | 0.449 [0.418, 0.480] | 0.190 [0.163, 0.219] | 0.397 [0.372, 0.423] | 0.176 [0.150, 0.203] | 0.383 [0.360, 0.406] | 0.161 [0.139, 0.185] |
| AMS3D |  | 0.232 [0.204, 0.262] | 0.060 [0.048, 0.074] | 0.349 [0.324, 0.374] | 0.112 [0.095, 0.129] | 0.443 [0.421, 0.466] | 0.172 [0.150, 0.196] |
| `ptrees` |  | 0.322 [0.286, 0.359] | 0.095 [0.074, 0.121] | 0.422 [0.396, 0.445] | 0.170 [0.149, 0.194] | 0.345 [0.324, 0.366] | 0.140 [0.119, 0.161] |
| `lmfauto` |  | 0.394 [0.355, 0.431] | 0.140 [0.115, 0.167] | 0.298 [0.268, 0.334] | 0.094 [0.074, 0.120] | 0.270 [0.241, 0.306] | 0.074 [0.059, 0.094] |

## Washington: each pick against the other candidates of its band

Paired differences, pick minus candidate, in F1 and in corrected F1:

| Band | Route | Pick | Versus | Pick minus candidate, F1 | Pick minus candidate, corrected F1 |
| --- | --- | --- | --- | --- | --- |
| A | GPU | SegmentAnyTree | ForestFormer3D | +0.003 [−0.023, +0.026] | +0.019 [−0.006, +0.046] |
| A | GPU | SegmentAnyTree | TreeisoNet | +0.029 [+0.005, +0.051] | +0.035 [+0.007, +0.064] |
| A | GPU | SegmentAnyTree | `multichm` | +0.059 [+0.029, +0.083] | +0.073 [+0.047, +0.098] |
| A | GPU | SegmentAnyTree | CHM-VWF | +0.030 [+0.006, +0.053] | +0.026 [−0.006, +0.053] |
| A | GPU | SegmentAnyTree | AMS3D | +0.271 [+0.229, +0.305] | +0.159 [+0.128, +0.188] |
| A | GPU | SegmentAnyTree | `ptrees` | +0.159 [+0.108, +0.206] | +0.117 [+0.078, +0.154] |
| A | GPU | SegmentAnyTree | `lmfauto` | +0.103 [+0.046, +0.145] | +0.080 [+0.048, +0.109] |
| B | GPU | ForestFormer3D | SegmentAnyTree (Washington best) | −0.013 [−0.031, +0.010] | −0.024 [−0.046, +0.001] |
| B | GPU | ForestFormer3D | TreeisoNet | −0.007 [−0.029, +0.019] | −0.013 [−0.036, +0.008] |
| B | GPU | ForestFormer3D | `multichm` | +0.028 [+0.015, +0.042] | +0.027 [+0.009, +0.045] |
| B | GPU | ForestFormer3D | CHM-VWF | +0.074 [+0.044, +0.108] | +0.017 [−0.009, +0.045] |
| B | GPU | ForestFormer3D | AMS3D | +0.128 [+0.105, +0.156] | +0.078 [+0.057, +0.099] |
| B | GPU | ForestFormer3D | `ptrees` | +0.030 [+0.010, +0.051] | +0.008 [−0.013, +0.029] |
| B | GPU | ForestFormer3D | `lmfauto` | +0.207 [+0.169, +0.241] | +0.101 [+0.082, +0.117] |
| C | GPU | `multichm` | ForestFormer3D | −0.010 [−0.025, +0.006] | −0.022 [−0.038, −0.007] |
| C | GPU | `multichm` | SegmentAnyTree | +0.101 [+0.077, +0.126] | +0.024 [+0.006, +0.041] |
| C | GPU | `multichm` | TreeisoNet (Washington best) | −0.024 [−0.055, +0.009] | −0.042 [−0.064, −0.018] |
| C | GPU | `multichm` | CHM-VWF | +0.058 [+0.030, +0.087] | −0.010 [−0.032, +0.010] |
| C | GPU | `multichm` | AMS3D | −0.009 [−0.033, +0.017] | −0.027 [−0.047, −0.009] |
| C | GPU | `multichm` | `ptrees` | +0.081 [+0.052, +0.111] | −0.004 [−0.023, +0.016] |
| C | GPU | `multichm` | `lmfauto` | +0.190 [+0.150, +0.220] | +0.074 [+0.055, +0.090] |
| A | CPU | `multichm` | CHM-VWF (Washington best) | −0.028 [−0.057, +0.001] | −0.047 [−0.073, −0.022] |
| A | CPU | `multichm` | `lmfauto` | +0.044 [−0.006, +0.087] | +0.007 [−0.025, +0.033] |
| A | CPU | `multichm` | `ptrees` | +0.100 [+0.057, +0.142] | +0.044 [+0.010, +0.076] |
| A | CPU | `multichm` | AMS3D | +0.212 [+0.183, +0.241] | +0.086 [+0.062, +0.111] |
| B | CPU | `multichm` | CHM-VWF | +0.046 [+0.017, +0.079] | −0.010 [−0.033, +0.014] |
| B | CPU | `multichm` | `lmfauto` | +0.178 [+0.138, +0.214] | +0.074 [+0.053, +0.091] |
| B | CPU | `multichm` | `ptrees` | +0.002 [−0.022, +0.029] | −0.019 [−0.040, +0.004] |
| B | CPU | `multichm` | AMS3D | +0.100 [+0.071, +0.129] | +0.051 [+0.029, +0.074] |
| C | CPU | `multichm` | CHM-VWF | +0.058 [+0.030, +0.087] | −0.010 [−0.032, +0.010] |
| C | CPU | `multichm` | `lmfauto` | +0.190 [+0.150, +0.220] | +0.074 [+0.055, +0.090] |
| C | CPU | `multichm` | `ptrees` | +0.081 [+0.052, +0.111] | −0.004 [−0.023, +0.016] |
| C | CPU | `multichm` | AMS3D (Washington best) | −0.009 [−0.033, +0.017] | −0.027 [−0.047, −0.009] |

## Every cell pooled

Each policy pools its cells over the whole density series of a scope, so the
six levels weigh equally: a route runs its band's pick in each cell, and a
fixed detector runs in every cell.

| Policy or detector | Five sites, F1 | Five sites, corrected F1 | California, F1 | California, corrected F1 | Washington, F1 | Washington, corrected F1 |
| --- | --- | --- | --- | --- | --- | --- |
| GPU route | 0.461 [0.444, 0.480] | 0.185 [0.167, 0.205] | 0.431 [0.394, 0.467] | 0.244 [0.210, 0.285] | 0.473 [0.453, 0.494] | 0.157 [0.138, 0.179] |
| CPU route | 0.445 [0.428, 0.464] | 0.166 [0.150, 0.184] | 0.424 [0.389, 0.461] | 0.228 [0.195, 0.264] | 0.454 [0.434, 0.475] | 0.137 [0.119, 0.158] |
| Native-only choice, GPU | 0.428 [0.407, 0.447] | 0.180 [0.162, 0.199] | 0.388 [0.355, 0.424] | 0.224 [0.185, 0.267] | 0.444 [0.420, 0.465] | 0.159 [0.140, 0.182] |
| Native-only choice, CPU | 0.445 [0.428, 0.464] | 0.166 [0.150, 0.184] | 0.424 [0.389, 0.461] | 0.228 [0.195, 0.264] | 0.454 [0.434, 0.475] | 0.137 [0.119, 0.158] |
| Single choice, GPU | 0.445 [0.428, 0.464] | 0.166 [0.150, 0.184] | 0.424 [0.389, 0.461] | 0.228 [0.195, 0.264] | 0.454 [0.434, 0.475] | 0.137 [0.119, 0.158] |
| Single choice, CPU | 0.445 [0.428, 0.464] | 0.166 [0.150, 0.184] | 0.424 [0.389, 0.461] | 0.228 [0.195, 0.264] | 0.454 [0.434, 0.475] | 0.137 [0.119, 0.158] |
| Washington best per band, GPU (descriptive) | 0.466 [0.442, 0.488] | 0.204 [0.181, 0.225] | 0.409 [0.372, 0.448] | 0.235 [0.194, 0.281] | 0.490 [0.463, 0.514] | 0.187 [0.163, 0.213] |
| Washington best per band, CPU (descriptive) | 0.447 [0.429, 0.465] | 0.176 [0.157, 0.196] | 0.408 [0.374, 0.445] | 0.220 [0.185, 0.259] | 0.461 [0.441, 0.481] | 0.156 [0.135, 0.180] |
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
| ForestFormer3D | +0.001 [−0.004, +0.007] | −0.004 [−0.010, +0.003] | +0.016 [+0.007, +0.025] | +0.007 [−0.003, +0.017] | −0.005 [−0.012, +0.002] | −0.008 [−0.017, −0.000] |
| SegmentAnyTree | +0.033 [+0.020, +0.048] | +0.005 [−0.005, +0.016] | +0.043 [+0.024, +0.062] | +0.020 [+0.001, +0.037] | +0.029 [+0.013, +0.047] | −0.002 [−0.014, +0.011] |
| TreeisoNet | +0.014 [−0.005, +0.034] | +0.001 [−0.014, +0.017] | +0.065 [+0.039, +0.095] | +0.045 [+0.022, +0.067] | −0.010 [−0.033, +0.015] | −0.020 [−0.039, −0.002] |
| `multichm` | +0.016 [+0.009, +0.023] | +0.020 [+0.012, +0.028] | +0.007 [−0.005, +0.019] | +0.016 [+0.001, +0.032] | +0.020 [+0.012, +0.027] | +0.021 [+0.012, +0.029] |
| CHM-VWF | +0.061 [+0.039, +0.080] | +0.013 [−0.005, +0.032] | +0.070 [+0.030, +0.108] | +0.026 [−0.013, +0.063] | +0.058 [+0.033, +0.083] | +0.005 [−0.014, +0.025] |
| AMS3D | +0.115 [+0.096, +0.134] | +0.072 [+0.059, +0.085] | +0.123 [+0.092, +0.151] | +0.102 [+0.076, +0.125] | +0.111 [+0.090, +0.134] | +0.058 [+0.043, +0.072] |
| `ptrees` | +0.091 [+0.078, +0.105] | +0.047 [+0.036, +0.059] | +0.132 [+0.112, +0.150] | +0.093 [+0.075, +0.111] | +0.075 [+0.058, +0.092] | +0.025 [+0.011, +0.039] |
| `lmfauto` | +0.169 [+0.135, +0.197] | +0.098 [+0.081, +0.112] | +0.084 [+0.058, +0.107] | +0.072 [+0.049, +0.094] | +0.193 [+0.156, +0.224] | +0.090 [+0.073, +0.104] |
| Native-only choice, GPU | +0.033 [+0.020, +0.048] | +0.005 [−0.005, +0.016] | +0.043 [+0.024, +0.062] | +0.020 [+0.001, +0.037] | +0.029 [+0.013, +0.047] | −0.002 [−0.014, +0.011] |
| CPU route | +0.016 [+0.009, +0.023] | +0.020 [+0.012, +0.028] | +0.007 [−0.005, +0.019] | +0.016 [+0.001, +0.032] | +0.020 [+0.012, +0.027] | +0.021 [+0.012, +0.029] |
| Single choice, GPU | +0.016 [+0.009, +0.023] | +0.020 [+0.012, +0.028] | +0.007 [−0.005, +0.019] | +0.016 [+0.001, +0.032] | +0.020 [+0.012, +0.027] | +0.021 [+0.012, +0.029] |
| Washington best per band, GPU (descriptive) | −0.005 [−0.020, +0.011] | −0.018 [−0.029, −0.006] | +0.021 [+0.005, +0.039] | +0.009 [−0.010, +0.026] | −0.016 [−0.036, +0.004] | −0.029 [−0.045, −0.014] |

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
| Washington best per band, CPU (descriptive) | −0.001 [−0.013, +0.009] | −0.010 [−0.019, −0.001] | +0.016 [+0.005, +0.027] | +0.008 [−0.006, +0.023] | −0.008 [−0.022, +0.006] | −0.019 [−0.029, −0.009] |

The GPU native-only choice (SegmentAnyTree at every level) minus each fixed
detector, every cell:

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

The GPU route minus the GPU native-only choice in each band; band A runs the
same detector in both:

| Band | Compute | Native-only choice | Route's pick | Scope | Route minus native-only, F1 | Route minus native-only, corrected F1 |
| --- | --- | --- | --- | --- | --- | --- |
| A | GPU | SegmentAnyTree | SegmentAnyTree | five sites | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| A | GPU | SegmentAnyTree | SegmentAnyTree | California | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| A | GPU | SegmentAnyTree | SegmentAnyTree | Washington | +0.000 [+0.000, +0.000] | +0.000 [+0.000, +0.000] |
| B | GPU | SegmentAnyTree | ForestFormer3D | five sites | −0.005 [−0.020, +0.013] | −0.014 [−0.031, +0.003] |
| B | GPU | SegmentAnyTree | ForestFormer3D | California | +0.011 [−0.015, +0.033] | +0.003 [−0.025, +0.028] |
| B | GPU | SegmentAnyTree | ForestFormer3D | Washington | −0.013 [−0.031, +0.010] | −0.024 [−0.046, +0.001] |
| C | GPU | SegmentAnyTree | `multichm` | five sites | +0.114 [+0.093, +0.136] | +0.039 [+0.023, +0.056] |
| C | GPU | SegmentAnyTree | `multichm` | California | +0.173 [+0.128, +0.214] | +0.078 [+0.044, +0.114] |
| C | GPU | SegmentAnyTree | `multichm` | Washington | +0.101 [+0.077, +0.126] | +0.024 [+0.006, +0.041] |

## Readings

- **What the routes pick.** With a GPU: SegmentAnyTree at QL1 density or
  denser, ForestFormer3D from QL2 to QL1, and `multichm` below QL2. With only
  a CPU: `multichm` in every band, so the CPU route is a single detector. The
  California margins behind the GPU picks are small, and no GPU pick
  separates from its runner-up on the development data: the paired
  differences are +0.008 [−0.028, +0.039] F1 in band A (SegmentAnyTree over
  ForestFormer3D), +0.001 [−0.018, +0.021] in band B (ForestFormer3D over
  `multichm`) and +0.025 [−0.006, +0.055] in band C (`multichm` over AMS3D).
  Only the CPU picks in bands A and B clearly beat their runner-up, CHM-VWF
  (+0.059 [+0.030, +0.088] and +0.067 [+0.015, +0.117]).
- **How far the picks are from the Washington best.** The band-A GPU pick is
  also the Washington best, at 0.512 [0.476, 0.546]. In band B, ForestFormer3D
  (0.489 [0.468, 0.512]) minus SegmentAnyTree is −0.013 [−0.031, +0.010]; in
  band C, `multichm` (0.448 [0.428, 0.470]) minus TreeisoNet (0.471 [0.441,
  0.501]) is −0.024 [−0.055, +0.009]. For the CPU route, `multichm` is the
  Washington best in band B; minus CHM-VWF in band A it is −0.028 [−0.057,
  +0.001], and minus AMS3D in band C −0.009 [−0.033, +0.017]. In observed F1
  every gap's interval includes zero. In corrected F1 three exclude it: below
  QL2, `multichm` minus TreeisoNet is −0.042 [−0.064, −0.018] and, marginally,
  minus AMS3D −0.027 [−0.047, −0.009], and in band A `multichm` minus CHM-VWF
  is −0.047 [−0.073, −0.022]. Over every Washington cell, the GPU route minus
  the per-band Washington best is −0.016 [−0.036, +0.004] in F1 and −0.029
  [−0.045, −0.014] in corrected F1; for the CPU route the two are −0.008
  [−0.022, +0.006] and, marginally, −0.019 [−0.029, −0.009]. The Washington
  bests are chosen on the same data, so these gaps overstate what a choice
  made without the Washington data could recover.
- **What the native-only choice loses below the QL2 floor.** The GPU
  native-only choice is SegmentAnyTree, which won the native-level comparison
  in California by 0.001 F1 over ForestFormer3D. Below the QL2 floor (band C),
  the route's `multichm` minus SegmentAnyTree is +0.101 [+0.077, +0.126] F1 in
  Washington and +0.173 [+0.128, +0.214] in California, and in corrected F1
  +0.024 [+0.006, +0.041], marginally, and +0.078 [+0.044, +0.114]. Above the
  floor the two are level: band A runs the same detector, and in band B the
  route minus the native-only choice is −0.013 [−0.031, +0.010] in
  Washington. Over every cell the route gains +0.029 [+0.013, +0.047] F1 in
  Washington, but in corrected F1 the difference is −0.002 [−0.014, +0.011]:
  in band B the route minus the native-only choice is −0.024 [−0.046, +0.001]
  in corrected F1, which balances the gain below the floor. Had the
  native-level choice fallen to ForestFormer3D, its row in the tables shows
  what that choice gives.
- **Whether one robust detector does as well as the routes.** ForestFormer3D
  at every level is level with the GPU route: the route minus ForestFormer3D
  is +0.001 [−0.004, +0.007] F1 on the five sites and −0.005 [−0.012, +0.002]
  in Washington, and in corrected F1 −0.004 [−0.010, +0.003] and, marginally,
  −0.008 [−0.017, −0.000]. TreeisoNet at every level is level with the route in
  Washington in F1 (−0.010 [−0.033, +0.015]) and, marginally, ahead of it in
  corrected F1 (−0.020 [−0.039, −0.002]), but behind it in California (+0.065
  [+0.039, +0.095]). Both were singled out after seeing the density series.
  Chosen by the routes' own rule on the California cells, the single choice is
  `multichm`, by 0.009 F1 over ForestFormer3D, and the GPU route leads it in
  Washington by +0.020 [+0.012, +0.027] F1 and +0.021 [+0.012, +0.029]
  corrected F1.
- **What routing adds and what it does not.** Routing by measured density
  avoids the one detector that collapses below the QL2 floor, a decision the
  ranking at native density cannot make: in California, SegmentAnyTree and
  ForestFormer3D are 0.001 F1 apart at native density. It adds no accuracy
  over the best single learned detector: with a GPU, ForestFormer3D at every
  density does as well as the route, and with only a CPU the route is
  `multichm` throughout. In Washington the gaps between the picks and the
  Washington best include zero in observed F1; in corrected F1 three do not:
  the two below the QL2 floor, where `multichm` registers to the mapped stems
  less well than TreeisoNet and, marginally, AMS3D, and the CPU pick at QL1
  density or denser, behind CHM-VWF.

## Caveats

- **Post hoc.** The design was fixed after the five-site results were known;
  only the selection of the picks is blind to Washington.
- **A small development region.** California holds 43 of the 106 plots and
  662 of the 2,525 stems. The margins of all three GPU picks lie inside their
  intervals, so another development sample could pick differently.
- **Development-region tuning.** The detector settings were fixed on
  California data, so California scores are in sample for the settings as
  well as for the selection.
- **Decimation.** Every cell below native density is a decimated copy of the
  native cloud, so band C holds decimated cells only. The comparison with
  native sparse flights suggests that decimation is optimistic, mildly for
  four detectors and strongly for SegmentAnyTree's recall, and no native
  acquisition at or below QL2 density covers the plots. Band C's picks and the
  native-only choice's loss there are measured on simulated sparse clouds.
- **The baseline's smoothing.** CHM-VWF runs with its pre-declared smoothing
  rule below 8 pulses/m², which costs it about 0.06 F1 on each of the four
  decimated levels where it was also run without the rule, all but the QL2
  level
  ([baseline smoothing sensitivity](baseline-smoothing-sensitivity-results.md)).
  Its band-B and band-C scores, and the CPU route's choice against it, are
  those of the smoothed configuration; the unsmoothed run has no null and no
  QL2-level cells, so it is not a candidate.
- **Chance agreement.** Corrected F1 measures registration to the mapped
  stems. The null tends to overstate the chance part of a score, so corrected
  scores are conservative, but whether a corrected difference is conservative
  depends on which detector is over-subtracted more.
- **Reference completeness.** Every score uses the nominal plot core, whose
  precision counts unmapped trees as errors and is a lower bound; the
  censused-subplot scores are not routed here.
- **Weighting.** The every-cell scores weigh the six levels of the density
  series equally, each stem counting once per level: band C holds 267 cells,
  band B 281 and band A 88. A national archive has another mix of densities,
  and its pooled score would weigh the bands differently.
- **Scope.** The sites are western U.S. conifer forest and oak woodland, and
  the reference is live mapped stems of at least 10 cm DBH; the picks are not
  tested in broadleaf or deciduous forest.

## Outputs

Under `work/paper_runs/density_routing/`:

- `routing_cells.csv`: one row per cell with its measured densities, band and
  each policy's detector.
- `routing_bands.csv`: cells, plots, stems and density per band and scope,
  with the cells of each level.
- `routing_picks.csv`: per route and band, the pick and runner-up with their
  California F1, the pick's Washington and five-site scores, the Washington
  best and the pick's paired difference to it.
- `routing_scores.csv`: per scope, every detector and policy in every band,
  over every cell and at every level: recall, precision, F1, null F1 and
  corrected F1 with intervals and counts.
- `routing_contrasts.csv`: per scope and band, and over every cell, each
  policy minus each fixed detector and the other policies, in F1 and corrected
  F1 with paired intervals; rows against a Washington best are flagged
  descriptive.
- `routing_check.csv`: per detector, level and scope, F1 and corrected F1
  beside the master-table and chance-agreement values they must equal.
- `density_routing.md`: the tables above; `routing_contract.json`: the
  design, the picks, the hashes of the inputs and the checksums of the code.
