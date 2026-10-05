# Cross-model density-ladder benchmark (SOAP, with cross-site extensions)

## Five sites, every arm (paper numbers)

Checked on 5 October 2026. Every arm on the declared `adopted` population of
the [frozen-clip study](frozen-clips-results.md) (106 plots, 2,525 stems at
SJER, SOAP, TEAK, WREF and ABBY), on equal support, with the
[master tables](master-tables-results.md)' paired plot-bootstrap intervals
(1,000 draws, plots resampled within site). Rungs are named by their
all-return target; the headers give the measured five-site median in
first-return pulses/m². The RGB arms and SAM2Point run once per plot and sit
in the native column. The sections after this one are the historical June
2026 benchmark on SOAP and the three-site population.

Native density, nominal box, five sites:

| Arm | Recall | Precision | F1 [95%] | F1 lead over CHM-VWF [95%] |
| --- | --- | --- | --- | --- |
| ForestFormer3D | 0.621 | 0.416 | 0.498 [0.478, 0.520] | +0.048 [+0.028, +0.069] |
| SegmentAnyTree | 0.604 | 0.419 | 0.495 [0.466, 0.522] | +0.044 [+0.021, +0.067] |
| `multichm` | 0.541 | 0.394 | 0.456 [0.435, 0.477] | +0.005 [−0.018, +0.028] |
| Li 2012 | 0.561 | 0.384 | 0.456 [0.426, 0.483] | +0.006 [−0.009, +0.019] |
| DeepForest | 0.545 | 0.390 | 0.454 [0.428, 0.478] | +0.004 [−0.014, +0.022] |
| CHM-VWF | 0.464 | 0.438 | 0.450 [0.423, 0.478] | — |
| TreeisoNet | 0.514 | 0.394 | 0.446 [0.420, 0.470] | −0.004 [−0.018, +0.009] |
| `lmfauto` | 0.555 | 0.296 | 0.386 [0.352, 0.421] | −0.064 [−0.095, −0.030] |
| Detectree2 | 0.309 | 0.435 | 0.362 [0.334, 0.390] | −0.089 [−0.120, −0.060] |
| `ptrees` | 0.712 | 0.215 | 0.331 [0.296, 0.369] | −0.120 [−0.154, −0.085] |
| AMS3D | 0.713 | 0.145 | 0.240 [0.214, 0.267] | −0.210 [−0.240, −0.180] |
| SAM2Point | 0.077 | 0.471 | 0.132 [0.110, 0.157] | −0.318 [−0.352, −0.279] |

F1 down the ladder, the eight full-ladder arms (intervals in
`master_long.csv`; paired changes from native in `master_rung_contrasts.csv`):

| Arm | native (9.8) | 8 (4.7) | 4 (2.5) | 2 (1.3) | 1 (0.6) | Lead over CHM-VWF at 0.6 [95%] |
| --- | --- | --- | --- | --- | --- | --- |
| ForestFormer3D | 0.498 | 0.487 | 0.457 | 0.438 | 0.421 | +0.047 [+0.022, +0.069] |
| SegmentAnyTree | 0.495 | 0.487 | 0.469 | 0.376 | 0.128 | −0.246 [−0.268, −0.223] |
| TreeisoNet | 0.446 | 0.452 | 0.453 | 0.444 | 0.440 | +0.066 [+0.037, +0.093] |
| `multichm` | 0.456 | 0.451 | 0.441 | 0.440 | 0.434 | +0.060 [+0.036, +0.082] |
| CHM-VWF | 0.450 | 0.395 | 0.396 | 0.383 | 0.374 | — |
| AMS3D | 0.240 | 0.313 | 0.389 | 0.459 | 0.437 | +0.063 [+0.033, +0.093] |
| `ptrees` | 0.331 | 0.444 | 0.414 | 0.360 | 0.271 | −0.103 [−0.122, −0.083] |
| `lmfauto` | 0.386 | 0.340 | 0.284 | 0.262 | 0.269 | −0.105 [−0.148, −0.063] |

Native F1 by site (intervals in `master_long.csv`):

| Arm | SJER | SOAP | TEAK | WREF | ABBY |
| --- | --- | --- | --- | --- | --- |
| ForestFormer3D | 0.325 | 0.454 | 0.495 | 0.491 | 0.542 |
| SegmentAnyTree | 0.274 | 0.469 | 0.517 | 0.463 | 0.559 |
| `multichm` | 0.342 | 0.437 | 0.449 | 0.452 | 0.489 |
| Li 2012 | 0.257 | 0.356 | 0.393 | 0.432 | 0.557 |
| DeepForest | 0.261 | 0.451 | 0.461 | 0.423 | 0.510 |
| CHM-VWF | 0.307 | 0.382 | 0.388 | 0.392 | 0.557 |
| TreeisoNet | 0.280 | 0.390 | 0.373 | 0.393 | 0.571 |
| `lmfauto` | 0.301 | 0.337 | 0.373 | 0.425 | 0.384 |
| Detectree2 | 0.250 | 0.405 | 0.337 | 0.314 | 0.426 |
| `ptrees` | 0.164 | 0.259 | 0.305 | 0.302 | 0.446 |
| AMS3D | 0.100 | 0.190 | 0.342 | 0.258 | 0.244 |
| SAM2Point | 0.214 | 0.259 | 0.158 | 0.127 | 0.071 |

**Readings.**

- At native density two learned segmenters, ForestFormer3D and
  SegmentAnyTree, lead CHM-VWF by about 0.05 F1, with intervals that exclude
  zero. `multichm`, Li 2012, DeepForest and TreeisoNet are indistinguishable
  from CHM-VWF.
- Down the ladder the arms part. SegmentAnyTree holds to 2.5 pulses/m² and
  collapses below it (0.376 at 1.3 and 0.128 at 0.6 pulses/m²). TreeisoNet
  and `multichm` are flat, and ForestFormer3D declines gently; all three lead
  CHM-VWF by 0.05 to 0.07 at 0.6 pulses/m². AMS3D rises as density falls,
  because it splits fewer crowns, and peaks at 1.3 pulses/m².
- The shape of the density response is consistent across sites for some
  arms and not for others (`master_rung_contrasts.csv`, per site). From native
  density to 0.6 pulses/m², SegmentAnyTree falls at every site (−0.33 to −0.43
  F1, −0.09 at the open SJER savanna), ForestFormer3D falls slightly everywhere
  (−0.02 to −0.10), TreeisoNet and `multichm` stay within ±0.05, and AMS3D
  rises at every site. CHM-VWF, `lmfauto` and `ptrees` change sign: they gain
  at SJER and lose at the closed-canopy sites.
- The ordering is not stable across sites. SJER, the open savanna, is the
  hardest site for every arm except SAM2Point; ABBY is the easiest for nine of
  the twelve. At ABBY,
  TreeisoNet, SegmentAnyTree, Li 2012 and CHM-VWF are within 0.015 of each
  other.
- Recall by crown class, regions, rank stability and censused precision are
  in the [master tables](master-tables-results.md).

## Historical benchmark (June 2026)

Cross-model synthesis (#R10) of every tree detector currently runnable on the
NEON SOAP density ladder, scored on the same frozen clips by the same field-stem
harness. The five-rung equal-set ladder now includes seven full arms:
AMS3D, `lmfauto`, `multichm`, `ptrees`, CHM-VWF, TreeisoNet, and
SegmentAnyTree. Li 2012 is reported native-only, and ForestFormer3D is reported
as an additive native + 8 pts/m2 comparison.

SegmentAnyTree (#M6 / #17) is no longer deferred: the rebuilt sm_120 Docker arm
completed the full SOAP ladder and wrote 90 rows to
`work/neon/SOAP/segmentanytree_results.csv` (18 plots x 5 rungs).
TreeisoNet and SegmentAnyTree have also now completed the cross-site SJER and
TEAK ladders: SJER wrote 39 rows per arm (8 plots, with one 8 pts/m2 cell
skipped by the density guard) and TEAK wrote 100 rows per arm (20 plots x
5 rungs). ForestFormer3D has now completed its native + 8 pts/m2 arm on all
three sites: SJER wrote 15 rows, SOAP wrote 36 rows, and TEAK wrote 40 rows.

The ForestFormer3D and TreeisoNet rows above and in the generated tables below
come from June 2026 runs that predate two adapter fixes. They are kept as
historical results. The [corrected-adapter re-runs](#corrected-adapter-re-runs-on-the-frozen-clips)
supersede them for both arms; quote those instead.

Regenerate:

```sh
export CLAUDE_JOB_DIR=$(pwd)/work
Rscript scripts/detect_ams3d_sweep.R       SITE=SOAP PLOTS=ALL CORES=12
Rscript scripts/detect_lidrplugins_sweep.R SITE=SOAP PLOTS=ALL CORES=12
Rscript scripts/detect_li2012_native.R     SITE=SOAP PLOTS=ALL CORES=12
for SITE in SOAP SJER TEAK; do
  Rscript scripts/detect_treeisonet_sweep.R        SITE=$SITE PLOTS=ALL VOXEL=0.8,0.8,2.0
  Rscript scripts/detect_segmentanytree_sweep.R    SITE=$SITE PLOTS=ALL IMAGE=sat-sm120-test CORES=4
  Rscript scripts/detect_forestformer3d_sweep.R    SITE=$SITE PLOTS=ALL REPO=<FF3D repo>
  Rscript scripts/analyze_model_benchmark.R        SITE=$SITE
done
Rscript scripts/compare_model_sites.R
```

## Corrected-adapter re-runs on the frozen clips

The June 2026 ForestFormer3D runs staged outer-cylinder tiles, which selected
the upstream fallback route and stitched conflicting labels. The re-runs use
the indexed whole-scene adapter. The TreeisoNet mask export now applies the
2 m height cutoff in the physical height frame and leaves unsupported points
unlabelled. Both arms were re-run on the
[frozen clips](frozen-clips-results.md): the declared 106-plot population with
2,525 field stems over five sites, at native density and 8/4/2/1 pts/m2. Each
run writes a manifest with the source revision, checkpoint hashes and
container image digest.

```sh
export CLAUDE_JOB_DIR=$(pwd)/work/paper_runs
for SITE in SJER SOAP TEAK WREF ABBY; do
  Rscript scripts/detect_forestformer3d_sweep.R SITE=$SITE RUNGS=native,8,4,2,1
  Rscript scripts/detect_treeisonet_sweep.R SITE=$SITE VOXEL=0.8,0.8,2.0 MASK_VOXEL=0
done
for SITE in SJER SOAP TEAK; do
  CLAUDE_JOB_DIR=$(pwd)/work/paper_runs_voxel0 \
    Rscript scripts/detect_treeisonet_sweep.R SITE=$SITE VOXEL=0 MASKS=0 RUNGS=native
done
Rscript scripts/compare_adapter_reruns.R BEFORE=work AFTER=work/paper_runs \
  VOXEL0=work/paper_runs_voxel0
```

The comparison re-scores the June native ForestFormer3D clouds and the
re-run clouds on the same plots, population, frozen terrain and scorer. Plots
without a June cloud are left out, so each site compares equal sets.

| site | plots | field stems | June recall | June precision | June F1 | re-run recall | re-run precision | re-run F1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SJER | 6 | 57 | 0.614 | 0.144 | 0.233 | 0.544 | 0.232 | 0.325 |
| SOAP | 18 | 231 | 0.407 | 0.191 | 0.260 | 0.636 | 0.352 | 0.454 |
| TEAK | 19 | 374 | 0.305 | 0.354 | 0.327 | 0.553 | 0.448 | 0.495 |

ForestFormer3D apex F1 at native density rises by 0.09 to 0.19 on every site.
Both recall and precision improve on SOAP and TEAK; on SJER the re-run trades
some recall for far fewer false detections.

TreeisoNet's apex pass runs treeLoc only, so the export fix does not touch it.
Its June rows changed for a different reason: the June SJER and TEAK runs used
the checkpoint's own 0.1 m voxel, while June SOAP and the re-runs use
0.8 x 0.8 x 2.0 m. A native-density re-run at the checkpoint voxel reproduces
the June SJER and TEAK apex counts cell for cell:

| site | plots | June F1 | re-run at checkpoint voxel | re-run at 0.8 x 0.8 x 2.0 m | cells with June apex count |
| --- | --- | --- | --- | --- | --- |
| SJER | 6 | 0.080 | 0.081 | 0.280 | checkpoint voxel 6 / 6 |
| SOAP | 18 | 0.393 | 0.125 | 0.390 | 0.8 m voxel 17 / 18 |
| TEAK | 19 | 0.120 | 0.122 | 0.373 | checkpoint voxel 19 / 19 |

The June reading that TreeisoNet "works on SOAP" but collapses on SJER and
TEAK therefore reflected the voxel setting, not site transfer. At one voxel
setting, TreeisoNet's native F1 is 0.28 to 0.57 on all five sites. June
reference counts differ slightly (59, 232 and 387 stems) because June used
the earlier stem gate.

Re-run ladder, both arms on the same 530 cells (106 plots, 2,525 stems; the
equal-set guard dropped no cell):

| rung | ForestFormer3D recall | precision | F1 | understory recall | TreeisoNet recall | precision | F1 | understory recall |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| native | 0.621 | 0.416 | 0.498 | 0.454 | 0.514 | 0.394 | 0.446 | 0.193 |
| 8 | 0.587 | 0.417 | 0.487 | 0.370 | 0.525 | 0.396 | 0.452 | 0.203 |
| 4 | 0.543 | 0.395 | 0.457 | 0.314 | 0.524 | 0.399 | 0.453 | 0.201 |
| 2 | 0.503 | 0.388 | 0.438 | 0.269 | 0.495 | 0.403 | 0.444 | 0.191 |
| 1 | 0.451 | 0.394 | 0.421 | 0.231 | 0.454 | 0.426 | 0.440 | 0.166 |

Native F1 by site:

| site | plots | field stems | ForestFormer3D | TreeisoNet |
| --- | --- | --- | --- | --- |
| SJER | 6 | 57 | 0.325 | 0.280 |
| SOAP | 18 | 231 | 0.454 | 0.390 |
| TEAK | 19 | 374 | 0.495 | 0.373 |
| WREF | 38 | 1,063 | 0.491 | 0.393 |
| ABBY | 25 | 800 | 0.542 | 0.571 |

**Re-run readings.**

- ForestFormer3D leads at native and 8 pts/m2. It finds more than twice
  TreeisoNet's share of understory stems at native density (0.45 against 0.19).
- ForestFormer3D loses 0.08 F1 from native to 1 pt/m2, while TreeisoNet is
  nearly flat. The two arms are level at 4 pts/m2, and TreeisoNet is slightly
  ahead at 2 and 1 pts/m2.
- ABBY is the only site where TreeisoNet beats ForestFormer3D.
- The TreeisoNet crown arm is unchanged by the fix. On the 94 SOAP stems both
  runs matched, the equivalent-diameter RMSE is 4.97 m against 4.99 m in June.
- These rows compare the two re-run arms only. The classical and other deep
  arms on the same frozen population are pooled in the master tables, not
  here.

## What this is

- **Population.** 18 SOAP plots, 232 field stems pooled, five density rungs:
  native plus all-return decimation targets of 8/4/2/1 pts/m2. The `frdens`
  column is first-return density and is used as the density-curve x-axis.
- **Scoring.** Each detector is reduced to apex detections `(x, y, z)` and
  scored by the unchanged `score_plot`/`greedy_match` 1:1 field-stem harness.
  Pooling sums counts, so recall is total true positives divided by total
  reference stems, never an average of per-plot rates.
- **Equal-set guard.** The ladder keeps only `(plot, rung)` cells scored by all
  seven ladder arms. This run dropped 0 cells, so every full-ladder arm is
  compared on the same 18-plot population at each rung.
- **Li 2012 and ForestFormer3D.** Li 2012 is native-only because the point
  segmenter is not meaningful at 1-2 pts/m2. ForestFormer3D is native + 8 only,
  so it stays outside the five-rung equal-set guard.

## Readings

- **SegmentAnyTree is the strongest native point/instance arm by F1.** Native
  recall/precision/F1 are 0.66/0.38/0.48, with understory recall 0.49. That
  beats CHM-VWF by +0.19 recall, +0.10 F1, and +0.22 understory recall at
  native density.
- **SegmentAnyTree is density-sensitive.** It remains competitive at 8 and
  4 pts/m2 (F1 0.43 and 0.45), then drops below CHM-VWF at 2 and 1 pts/m2.
  The lowest rung has high precision but very low recall.
- **SegmentAnyTree now transfers across sites better than the other deep
  point arm.** Native F1 is 0.48 on both SOAP and TEAK and 0.29 on SJER; SJER's
  lower F1 is mostly precision-limited in the open savanna, not recall-limited.
- **`multichm` is still the most stable classical ladder arm.** It beats CHM-VWF
  on F1 at every rung and keeps recall nearly flat across density.
- **Historical TreeisoNet and ForestFormer3D readings (June 2026).** These two
  readings are superseded by the
  [corrected-adapter re-runs](#corrected-adapter-re-runs-on-the-frozen-clips).
  June TreeisoNet stayed near F1 0.39-0.41 on SOAP and failed on SJER and TEAK,
  but those two sites ran at a different voxel setting. June ForestFormer3D
  (native F1 0.25 on SJER and 0.30 on TEAK) used the outer-cylinder adapter.

## Generated Tables

The tables below are copied from
`work/neon/SOAP/model_bench_tables.md`, generated by
`scripts/analyze_model_benchmark.R`.

### Density ladder, per crown class (pooled, equal-set)

| detector | rung | frdens | n_plots | n_ref | recall | precision | F1 | rec_dominant | rec_codominant | rec_understory |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ams3d | native | 11.78 | 18 | 232 | 0.79 | 0.11 | 0.19 | 0.79 | 0.82 | 0.69 |
| ams3d | 8 | 5.79 | 18 | 232 | 0.81 | 0.18 | 0.29 | 0.83 | 0.82 | 0.71 |
| ams3d | 4 | 3.00 | 18 | 232 | 0.74 | 0.24 | 0.37 | 0.79 | 0.75 | 0.62 |
| ams3d | 2 | 1.53 | 18 | 232 | 0.68 | 0.35 | 0.46 | 0.76 | 0.67 | 0.53 |
| ams3d | 1 | 0.78 | 18 | 232 | 0.44 | 0.42 | 0.43 | 0.52 | 0.43 | 0.33 |
| chm_vwf | native | 11.78 | 18 | 232 | 0.48 | 0.32 | 0.38 | 0.54 | 0.51 | 0.27 |
| chm_vwf | 8 | 5.79 | 18 | 232 | 0.33 | 0.48 | 0.39 | 0.44 | 0.33 | 0.13 |
| chm_vwf | 4 | 3.00 | 18 | 232 | 0.35 | 0.48 | 0.40 | 0.45 | 0.35 | 0.16 |
| chm_vwf | 2 | 1.53 | 18 | 232 | 0.34 | 0.46 | 0.39 | 0.46 | 0.33 | 0.13 |
| chm_vwf | 1 | 0.78 | 18 | 232 | 0.34 | 0.45 | 0.39 | 0.42 | 0.33 | 0.18 |
| lmfauto | native | 11.78 | 18 | 232 | 0.51 | 0.25 | 0.34 | 0.56 | 0.55 | 0.29 |
| lmfauto | 8 | 5.79 | 18 | 232 | 0.57 | 0.26 | 0.36 | 0.58 | 0.64 | 0.36 |
| lmfauto | 4 | 3.00 | 18 | 232 | 0.66 | 0.25 | 0.37 | 0.76 | 0.70 | 0.40 |
| lmfauto | 2 | 1.53 | 18 | 232 | 0.76 | 0.23 | 0.35 | 0.87 | 0.79 | 0.51 |
| lmfauto | 1 | 0.78 | 18 | 232 | 0.81 | 0.19 | 0.31 | 0.89 | 0.82 | 0.62 |
| multichm | native | 11.78 | 18 | 232 | 0.63 | 0.34 | 0.44 | 0.68 | 0.67 | 0.44 |
| multichm | 8 | 5.79 | 18 | 232 | 0.61 | 0.32 | 0.42 | 0.62 | 0.67 | 0.44 |
| multichm | 4 | 3.00 | 18 | 232 | 0.64 | 0.35 | 0.45 | 0.66 | 0.71 | 0.42 |
| multichm | 2 | 1.53 | 18 | 232 | 0.65 | 0.37 | 0.47 | 0.65 | 0.66 | 0.58 |
| multichm | 1 | 0.78 | 18 | 232 | 0.60 | 0.36 | 0.45 | 0.62 | 0.64 | 0.47 |
| ptrees | native | 11.78 | 18 | 232 | 0.85 | 0.15 | 0.26 | 0.83 | 0.88 | 0.78 |
| ptrees | 8 | 5.79 | 18 | 232 | 0.61 | 0.26 | 0.36 | 0.65 | 0.65 | 0.42 |
| ptrees | 4 | 3.00 | 18 | 232 | 0.50 | 0.34 | 0.41 | 0.58 | 0.54 | 0.27 |
| ptrees | 2 | 1.53 | 18 | 232 | 0.31 | 0.37 | 0.34 | 0.45 | 0.28 | 0.11 |
| ptrees | 1 | 0.78 | 18 | 232 | 0.21 | 0.38 | 0.27 | 0.28 | 0.21 | 0.07 |
| segmentanytree | native | 11.78 | 18 | 232 | 0.66 | 0.38 | 0.48 | 0.65 | 0.73 | 0.49 |
| segmentanytree | 8 | 5.79 | 18 | 232 | 0.56 | 0.35 | 0.43 | 0.59 | 0.61 | 0.36 |
| segmentanytree | 4 | 3.00 | 18 | 232 | 0.51 | 0.41 | 0.45 | 0.65 | 0.49 | 0.36 |
| segmentanytree | 2 | 1.53 | 18 | 232 | 0.27 | 0.41 | 0.33 | 0.31 | 0.30 | 0.13 |
| segmentanytree | 1 | 0.78 | 18 | 232 | 0.07 | 0.59 | 0.13 | 0.11 | 0.06 | 0.04 |
| treeisonet | native | 11.78 | 18 | 232 | 0.60 | 0.29 | 0.39 | 0.72 | 0.62 | 0.33 |
| treeisonet | 8 | 5.79 | 18 | 232 | 0.61 | 0.29 | 0.39 | 0.73 | 0.63 | 0.33 |
| treeisonet | 4 | 3.00 | 18 | 232 | 0.62 | 0.30 | 0.41 | 0.76 | 0.65 | 0.31 |
| treeisonet | 2 | 1.53 | 18 | 232 | 0.60 | 0.31 | 0.41 | 0.76 | 0.60 | 0.31 |
| treeisonet | 1 | 0.78 | 18 | 232 | 0.52 | 0.33 | 0.40 | 0.66 | 0.53 | 0.24 |

### Density ladder, per height band

| detector | rung | rec_h_tall | n_h_tall | rec_h_mid | n_h_mid | rec_h_short | n_h_short |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ams3d | native | 0.58 | 60 | 0.79 | 90 | 0.94 | 79 |
| ams3d | 8 | 0.63 | 60 | 0.80 | 90 | 0.94 | 79 |
| ams3d | 4 | 0.63 | 60 | 0.78 | 90 | 0.77 | 79 |
| ams3d | 2 | 0.70 | 60 | 0.74 | 90 | 0.57 | 79 |
| ams3d | 1 | 0.67 | 60 | 0.47 | 90 | 0.24 | 79 |
| chm_vwf | native | 0.63 | 60 | 0.38 | 90 | 0.46 | 79 |
| chm_vwf | 8 | 0.43 | 60 | 0.29 | 90 | 0.28 | 79 |
| chm_vwf | 4 | 0.48 | 60 | 0.30 | 90 | 0.29 | 79 |
| chm_vwf | 2 | 0.53 | 60 | 0.23 | 90 | 0.29 | 79 |
| chm_vwf | 1 | 0.50 | 60 | 0.30 | 90 | 0.23 | 79 |
| lmfauto | native | 0.62 | 60 | 0.44 | 90 | 0.48 | 79 |
| lmfauto | 8 | 0.67 | 60 | 0.53 | 90 | 0.52 | 79 |
| lmfauto | 4 | 0.80 | 60 | 0.54 | 90 | 0.68 | 79 |
| lmfauto | 2 | 0.83 | 60 | 0.73 | 90 | 0.73 | 79 |
| lmfauto | 1 | 0.92 | 60 | 0.74 | 90 | 0.78 | 79 |
| multichm | native | 0.73 | 60 | 0.60 | 90 | 0.58 | 79 |
| multichm | 8 | 0.77 | 60 | 0.57 | 90 | 0.54 | 79 |
| multichm | 4 | 0.82 | 60 | 0.57 | 90 | 0.58 | 79 |
| multichm | 2 | 0.82 | 60 | 0.64 | 90 | 0.51 | 79 |
| multichm | 1 | 0.83 | 60 | 0.52 | 90 | 0.51 | 79 |
| ptrees | native | 0.87 | 60 | 0.83 | 90 | 0.85 | 79 |
| ptrees | 8 | 0.73 | 60 | 0.54 | 90 | 0.58 | 79 |
| ptrees | 4 | 0.62 | 60 | 0.38 | 90 | 0.54 | 79 |
| ptrees | 2 | 0.45 | 60 | 0.24 | 90 | 0.25 | 79 |
| ptrees | 1 | 0.37 | 60 | 0.13 | 90 | 0.16 | 79 |
| segmentanytree | native | 0.80 | 60 | 0.62 | 90 | 0.59 | 79 |
| segmentanytree | 8 | 0.72 | 60 | 0.57 | 90 | 0.42 | 79 |
| segmentanytree | 4 | 0.68 | 60 | 0.50 | 90 | 0.39 | 79 |
| segmentanytree | 2 | 0.35 | 60 | 0.30 | 90 | 0.18 | 79 |
| segmentanytree | 1 | 0.05 | 60 | 0.09 | 90 | 0.08 | 79 |
| treeisonet | native | 0.67 | 60 | 0.60 | 90 | 0.53 | 79 |
| treeisonet | 8 | 0.70 | 60 | 0.59 | 90 | 0.54 | 79 |
| treeisonet | 4 | 0.75 | 60 | 0.56 | 90 | 0.58 | 79 |
| treeisonet | 2 | 0.63 | 60 | 0.60 | 90 | 0.56 | 79 |
| treeisonet | 1 | 0.53 | 60 | 0.49 | 90 | 0.53 | 79 |

### Native point-segmenter head-to-head

| detector | n_plots | n_ref | recall | precision | F1 | rec_understory | n_understory |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ams3d | 18 | 232 | 0.79 | 0.11 | 0.19 | 0.69 | 45 |
| chm_vwf | 18 | 232 | 0.48 | 0.32 | 0.38 | 0.27 | 45 |
| li2012 | 18 | 232 | 0.59 | 0.26 | 0.36 | 0.33 | 45 |
| ptrees | 18 | 232 | 0.85 | 0.15 | 0.26 | 0.78 | 45 |
| segmentanytree | 18 | 232 | 0.66 | 0.38 | 0.48 | 0.49 | 45 |
| treeisonet | 18 | 232 | 0.60 | 0.29 | 0.39 | 0.33 | 45 |

### Head-to-head deltas vs CHM-VWF (recall/F1/understory)

| detector | rung | d_recall | d_F1 | d_understory |
| --- | --- | --- | --- | --- |
| ams3d | native | 0.31 | -0.19 | 0.42 |
| ams3d | 8 | 0.47 | -0.10 | 0.58 |
| ams3d | 4 | 0.39 | -0.04 | 0.47 |
| ams3d | 2 | 0.34 | 0.08 | 0.40 |
| ams3d | 1 | 0.11 | 0.04 | 0.16 |
| lmfauto | native | 0.03 | -0.04 | 0.02 |
| lmfauto | 8 | 0.24 | -0.03 | 0.22 |
| lmfauto | 4 | 0.31 | -0.04 | 0.24 |
| lmfauto | 2 | 0.43 | -0.04 | 0.38 |
| lmfauto | 1 | 0.47 | -0.07 | 0.44 |
| multichm | native | 0.15 | 0.06 | 0.18 |
| multichm | 8 | 0.28 | 0.03 | 0.31 |
| multichm | 4 | 0.29 | 0.05 | 0.27 |
| multichm | 2 | 0.31 | 0.08 | 0.44 |
| multichm | 1 | 0.27 | 0.07 | 0.29 |
| ptrees | native | 0.37 | -0.12 | 0.51 |
| ptrees | 8 | 0.28 | -0.03 | 0.29 |
| ptrees | 4 | 0.16 | 0.00 | 0.11 |
| ptrees | 2 | -0.03 | -0.05 | -0.02 |
| ptrees | 1 | -0.12 | -0.12 | -0.11 |
| segmentanytree | native | 0.19 | 0.10 | 0.22 |
| segmentanytree | 8 | 0.22 | 0.04 | 0.22 |
| segmentanytree | 4 | 0.16 | 0.05 | 0.20 |
| segmentanytree | 2 | -0.06 | -0.06 | 0.00 |
| segmentanytree | 1 | -0.26 | -0.26 | -0.13 |
| treeisonet | native | 0.12 | 0.01 | 0.07 |
| treeisonet | 8 | 0.28 | -0.00 | 0.20 |
| treeisonet | 4 | 0.27 | 0.00 | 0.16 |
| treeisonet | 2 | 0.26 | 0.02 | 0.18 |
| treeisonet | 1 | 0.18 | 0.02 | 0.07 |

### ForestFormer3D (#M8) native + 8, vs baselines

| detector | rung | frdens | n_plots | n_ref | recall | precision | F1 | rec_dominant | rec_codominant | rec_understory |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| chm_vwf | native | 11.78 | 18 | 232 | 0.48 | 0.32 | 0.38 | 0.54 | 0.51 | 0.27 |
| chm_vwf | 8 | 5.79 | 18 | 232 | 0.33 | 0.48 | 0.39 | 0.44 | 0.33 | 0.13 |
| forestformer3d | native | 11.78 | 18 | 232 | 0.44 | 0.20 | 0.28 | 0.45 | 0.50 | 0.24 |
| forestformer3d | 8 | 5.79 | 18 | 232 | 0.44 | 0.24 | 0.31 | 0.54 | 0.46 | 0.22 |
| treeisonet | native | 11.78 | 18 | 232 | 0.60 | 0.29 | 0.39 | 0.72 | 0.62 | 0.33 |
| treeisonet | 8 | 5.79 | 18 | 232 | 0.61 | 0.29 | 0.39 | 0.73 | 0.63 | 0.33 |

## Cross-site deep-arm extension

TreeisoNet and SegmentAnyTree now have full ladder outputs on SJER, SOAP, and
TEAK. ForestFormer3D has native + 8 pts/m2 outputs on the same three sites. The
generated per-site tables are:
`work/neon/SJER/model_bench_tables.md`,
`work/neon/SOAP/model_bench_tables.md`, and
`work/neon/TEAK/model_bench_tables.md`.

Result coverage:

| site | TreeisoNet rows | SegmentAnyTree rows | ForestFormer3D rows | notes |
| --- | --- | --- | --- | --- |
| SJER | 39 | 39 | 15 | 8 plots; rung 8 has 7 cells after density guard |
| SOAP | 90 | 90 | 36 | 18 plots; FF3D native + 8 only |
| TEAK | 100 | 100 | 40 | 20 plots; FF3D native + 8 only |

### Native density, deep arms x site

| detector | site | frdens | n_plots | n_ref | recall | precision | F1 | rec_understory | n_understory |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| forestformer3d | SJER | 8.62 | 8 | 71 | 0.65 | 0.16 | 0.25 | 0.50 | 2 |
| forestformer3d | SOAP | 11.78 | 18 | 232 | 0.42 | 0.20 | 0.27 | 0.20 | 45 |
| forestformer3d | TEAK | 11.65 | 20 | 396 | 0.29 | 0.31 | 0.30 | 0.19 | 58 |
| segmentanytree | SJER | 8.62 | 8 | 71 | 0.70 | 0.18 | 0.29 | 1.00 | 2 |
| segmentanytree | SOAP | 11.78 | 18 | 232 | 0.66 | 0.38 | 0.48 | 0.49 | 45 |
| segmentanytree | TEAK | 11.65 | 20 | 396 | 0.65 | 0.38 | 0.48 | 0.40 | 58 |
| treeisonet | SJER | 8.62 | 8 | 71 | 0.11 | 0.06 | 0.07 | 0.00 | 2 |
| treeisonet | SOAP | 11.78 | 18 | 232 | 0.60 | 0.29 | 0.39 | 0.33 | 45 |
| treeisonet | TEAK | 11.65 | 20 | 396 | 0.13 | 0.12 | 0.12 | 0.02 | 58 |

**Deep-arm readings.**

- **SegmentAnyTree is the strongest full-ladder deep arm across the structure
  gradient.** Native recall stays high from SJER to TEAK (0.70, 0.66, 0.65),
  while precision rises with denser stem fields (0.18, 0.38, 0.38). Its native
  F1 is essentially tied between SOAP and TEAK (0.48) and lower in SJER because
  the open savanna produces many unmatched detections.
- **SegmentAnyTree remains density-sensitive everywhere.** Native-to-rung-1 F1
  drops 0.29 -> 0.23 on SJER, 0.48 -> 0.13 on SOAP, and 0.48 -> 0.07 on TEAK.
  The 8 and 4 pts/m2 rungs are the useful sparse range; 1 pts/m2 is too sparse
  for this zero-shot arm.
- **Historical (June 2026): TreeisoNet appeared site-specific.** It was
  competitive on SOAP (native F1 0.39) and collapsed on SJER and TEAK (0.07 and
  0.12). The re-runs trace the collapse to the checkpoint voxel used on those
  two sites; at one setting the arm is not site-specific.
- **Historical (June 2026): ForestFormer3D trailed CHM-VWF.** Native F1 was
  0.25 / 0.27 / 0.30 on SJER / SOAP / TEAK, versus CHM-VWF's 0.32 / 0.38 /
  0.37, with the outer-cylinder adapter. See the
  [corrected-adapter re-runs](#corrected-adapter-re-runs-on-the-frozen-clips).
- **SJER understory remains too small for strong interpretation.** The SJER
  understory count is only 2 stems, so the 1.00 SegmentAnyTree understory recall
  at native density is reported for completeness but should not be compared
  directly with SOAP/TEAK's larger understory samples.

## Cross-site structure gradient (SJER → SOAP → TEAK)

The five classical arms (CHM-VWF, lmfauto, multichm, ptrees, AMS3D) were run on
all three NEON sites across the full density ladder and pooled by
`compare_model_sites.R` (each site equal-set-guarded to its own all-five-arm
plot population: SJER 8 plots / 71 stems, SOAP 18 / 232, TEAK 20 / 396; SJER
rung 8 keeps 7 plots after the guard). This section remains the classical-arm
structure-gradient view; TreeisoNet, SegmentAnyTree, and ForestFormer3D are
summarized in the deep-arm section above, while Li 2012 remains SOAP-only.

**This is a structure gradient at matched density, not a density gradient.** All
three native clouds sit at essentially the same density — ~18–19 all-return
pts/m² (`pdens`), i.e. first-return ~8.6 (SJER), ~11.8 (SOAP), ~11.7 (TEAK)
pulses/m² (`frdens`, the curve x-axis). So differences across sites isolate
canopy structure — SJER open oak savanna → SOAP mixed conifer → TEAK dense red
fir — rather than input density.

### Native density, all arms × site

| detector | site | frdens | n_ref | recall | precision | F1 | rec_understory |
| --- | --- | --- | --- | --- | --- | --- | --- |
| chm_vwf | SJER | 8.62 | 71 | 0.49 | 0.24 | 0.32 | n=2 |
| chm_vwf | SOAP | 11.78 | 232 | 0.48 | 0.32 | 0.38 | 0.27 |
| chm_vwf | TEAK | 11.65 | 396 | 0.34 | 0.40 | 0.37 | 0.12 |
| lmfauto | SJER | 8.62 | 71 | 0.61 | 0.21 | 0.31 | n=2 |
| lmfauto | SOAP | 11.78 | 232 | 0.51 | 0.25 | 0.34 | 0.29 |
| lmfauto | TEAK | 11.65 | 396 | 0.35 | 0.35 | 0.35 | 0.10 |
| multichm | SJER | 8.62 | 71 | 0.69 | 0.23 | 0.35 | n=2 |
| multichm | SOAP | 11.78 | 232 | 0.63 | 0.34 | 0.44 | 0.44 |
| multichm | TEAK | 11.65 | 396 | 0.46 | 0.38 | 0.42 | 0.22 |
| ptrees | SJER | 8.62 | 71 | 0.83 | 0.10 | 0.18 | n=2 |
| ptrees | SOAP | 11.78 | 232 | 0.85 | 0.15 | 0.26 | 0.78 |
| ptrees | TEAK | 11.65 | 396 | 0.52 | 0.20 | 0.29 | 0.26 |
| ams3d | SJER | 8.62 | 71 | 0.97 | 0.06 | 0.11 | n=2 |
| ams3d | SOAP | 11.78 | 232 | 0.79 | 0.11 | 0.19 | 0.69 |
| ams3d | TEAK | 11.65 | 396 | 0.70 | 0.22 | 0.34 | 0.78 |

SJER understory is only 2 mapped stems, below the n≥5 reporting threshold, so
its `rec_understory` is shown as `n=2` and omitted from the figure's dashed
lines (same convention as `compare_sites.R`).

**Findings.**

- **Recall declines monotonically with canopy closure.** Holding arm and
  density fixed, every arm loses recall SJER → SOAP → TEAK (e.g. AMS3D 0.97 →
  0.79 → 0.70; multichm 0.69 → 0.63 → 0.46; CHM-VWF 0.49 → 0.48 → 0.34). The one
  near-tie is ptrees at SJER vs SOAP (0.83 vs 0.85); TEAK still drops it to 0.52.
  TEAK's closed red-fir canopy is the hard floor for all arms.
- **Each arm's density response is site-invariant in shape, only shifted in
  level.** Across all three sites the same ordering holds: ptrees and AMS3D
  *lose* recall as the cloud is decimated (point-hungry: ptrees native→rung-1
  0.83→0.30 SJER, 0.85→0.21 SOAP, 0.52→0.09 TEAK), while lmfauto *gains* recall
  at sparse rungs by over-detecting (0.61→0.86 SJER, 0.51→0.81 SOAP, 0.35→0.63
  TEAK, all at falling precision); multichm and CHM-VWF stay roughly flat. The
  structure gradient sets the level; density sets the slope.
- **Precision rises with closure**, partly offsetting recall: the over-detecting
  arms (AMS3D, ptrees) post their best precision at TEAK (0.22, 0.20) because the
  denser stem field absorbs more of their many apexes — so F1 compresses the
  site gap (AMS3D F1 0.11 → 0.19 → 0.34 actually *improves* toward TEAK).

Regenerate with `compare_model_sites.R` (see the Regenerate block above); it
writes `model_cross_site_summary.csv` and the per-arm + summary
`model_structure_gradient*.png` density curves under `neon/figs/`.

## Classical Treeiso, the unsupervised 3-D baseline (#P5)

The learned TreeisoNet (#M7) was already here; the **classical** cut-pursuit
Treeiso (Xi & Hopkinson 2022; vendored MIT under `external/treeiso/`, run by
`detect_treeiso_sweep.R`) is the non-learned 3-D instance segmenter FGI-EMIT uses
as its baseline. Its graph-cut errors are decorrelated from the CHM/local-maximum
arms, so it is a diversity member for the #P1 consensus pool — but it was
designed for dense TLS/ULS, and on sparse discrete-return ALS it **collapses**.

| site (native) | n_ref | recall | precision | F1 | understory recall |
|---|--:|--:|--:|--:|--:|
| SOAP | 232 | 0.086 | 0.594 | 0.151 | 0.000 |
| SJER | 71 | 0.042 | 0.273 | 0.073 | 0.000 |
| TEAK | 370 | 0.173 | 0.423 | 0.246 | 0.019 |

SOAP density ladder — recall halves as the cloud thins:

| rung | native | 8 | 4 | 2 | 1 |
|---|--:|--:|--:|--:|--:|
| recall | 0.086 | 0.050 | 0.052 | 0.030 | 0.037 |
| F1 | 0.151 | 0.091 | 0.095 | 0.056 | 0.069 |

Readings:

- **The deep arms decisively beat the classical 3-D segmenter on ALS** — the
  question #P5 was built to answer. SegmentAnyTree's native SOAP recall (0.642)
  is **7.5×** Treeiso's (0.086); F1 0.464 vs 0.151. Treeiso's cut-pursuit needs
  the visible stems and dense returns of TLS to separate trees; on ALS canopy it
  **severely under-segments** (e.g. SOAP_031: 34 mapped core stems but only 36
  instances over the whole 70k-point clip, 7 with an apex in core), merging
  touching crowns it cannot cut apart without stem evidence.
- **It contributes precision, not recall.** Precision is moderate (~0.4–0.6) — the
  few instances it does isolate are usually real trees — and **understory recall
  is ≈0** at every site and rung. As a fusion member it adds a small, decorrelated
  high-precision set, not coverage.
- **It degrades with density**, recall falling from 0.086 (native) to 0.037
  (1 pt/m²) on SOAP, and is best on TEAK's taller, better-separated conifers
  (0.173) and worst on open SJER (0.042). Default Treeiso parameters (TLS-tuned)
  are used unchanged — the honest out-of-the-box classical baseline, not a
  re-tuned arm.

## Caveats

- The sparse rungs are decimated from the native cloud, so they remove returns
  without changing the original acquisition geometry.
- Deep arms are zero-shot on NEON ALS. These results measure transfer to sparse
  discrete-return airborne LiDAR, not performance at the dense ULS/UAS/TLS
  densities many source models were designed for.
- Scoring here reduces every model to apex detections against mapped stems; it
  does not evaluate point-level instance IoU or crown-shape quality. The deep
  arms' persisted per-point instance clouds are now also graded that way —
  point-set IoU≥0.5, Coverage, and Panoptic Quality against a Voronoi-on-stems
  reference — by the #V1 scorer in
  [`instance-iou-pq-results.md`](instance-iou-pq-results.md), which finds the
  apex-distance recall above overstates instance quality roughly two- to
  threefold.
- The cross-site structure gradient (SJER → SOAP → TEAK) above extends the five
  classical arms to all three sites; TreeisoNet and SegmentAnyTree now also have
  full SJER/SOAP/TEAK ladders. ForestFormer3D has SJER/SOAP/TEAK native + 8
  results, and Li 2012 remains SOAP-only in this report.
