# Frozen plot population and clips

Checked on 1 October 2026. Before any benchmark arm re-runs for the paper,
this study fixes two things every arm must share: the plot population and the
bytes of every plot clip at every density rung. The CHM variable-window
(CHM-VWF) and `multichm` density ladders used to decimate their own unseeded
clips on every run, while the model benchmark read seeded, cached clips, so
two arms never scored quite the same input. Every NEON arm now reads one
sealed, hash-verified clip root and one declared population.

**Decision: keep the six-stem plot gate.** The headline population stays as
the [Pacific Northwest preflight](pacific-northwest-extension-results.md)
adopted it: live mapped stems of at least 10 cm DBH, in plots holding at
least six of them. That is 106 plots and 2,525 core stems at five sites.
Dropping the six-stem gate would add 43 plots holding 103 stems (4.1%), one to
five stems each. Those plots are frozen too, so the relaxed gate can be
reported as a sensitivity row; it is not a headline gain.

**Acceptance: the frozen clips reproduce the historical CHM-VWF ladder.**
Regenerated on the frozen clips for the historical D17 population, every plot
and stem matches, native rows match exactly up to lasR's own run-to-run
jitter, and 11 of the 12 decimated site × rung cells lie inside the measured
decimation noise. The exception, SOAP at 4 points/m², is a high draw of the
old pipeline: its cached F1 of 0.424 sits above all 21 seeded and legacy-path
draws, which centre on 0.38–0.39. The old pipeline and the frozen clips draw
from the same distribution.

## Declared populations

Every population applies a stem gate, then a whole-plot gate on the number of
gated live mapped trees, and keeps plots with at least one gated stem inside
the nominal core (tower ±20 m, distributed ±10 m). The scored reference is
the gated stems inside the core.

| Population | Stem gate | Plot gate | Role |
| --- | --- | --- | --- |
| `adopted` | live, mapped, DBH ≥ 10 cm | ≥ 6 gated trees | Headline for every later table |
| `all_mapped` | live, mapped | ≥ 6 live mapped trees | Sensitivity; the historical D17 population |
| `relaxed` | live, mapped, DBH ≥ 10 cm | ≥ 1 gated tree | Sensitivity; no six-stem gate |

| Site | `adopted` plots (tower / distributed) | `adopted` core stems | `all_mapped` plots / stems | `relaxed` plots / stems |
| --- | --- | --- | --- | --- |
| SJER | 6 (6 / 0) | 57 | 8 / 71 | 21 / 89 |
| SOAP | 18 (7 / 11) | 231 | 18 / 232 | 27 / 251 |
| TEAK | 19 (6 / 13) | 374 | 20 / 396 | 36 / 419 |
| WREF | 38 (20 / 18) | 1,063 | 38 / 1,081 | 39 / 1,068 |
| ABBY | 25 (13 / 12) | 800 | 32 / 1,074 | 26 / 801 |
| **Total** | **106 (52 / 54)** | **2,525** | **116 / 2,854** | **149 / 2,628** |

The `all_mapped` rows reproduce the historical D17 sweep exactly: 8, 18 and 20
plots with 71, 232 and 396 core stems, 46 plots and 699 stems in all. Under
the adopted gate D17 keeps 43 plots and 662 stems; SJER_008, SJER_054 and
TEAK_050 drop out, as do the seven ABBY sapling stands the preflight
excluded. WREF_008 passes neither six-stem gate. The clips cover the union of
the three populations: 155 plots.

### The six-stem gate

The six-stem gate counts gated live mapped trees over the whole plot, before
the core cut, as the historical sweep did. Lowering it to one stem adds 15
SJER, 9 SOAP, 17 TEAK, 1 WREF and 1 ABBY plot, with 32, 20, 45, 5 and 1 core
stems. That is 4.1% more reference, spread over plots whose cores hold one to
five stems. Such plots carry almost no recall information each and are
dominated by unmapped detections at the core edge, and the WREF and ABBY
extension has already multiplied the reference nearly fourfold. The gate
therefore stays; `relaxed` is frozen so that any arm can report it with
`POP=relaxed` at no extra cost.

## Frozen clips

[freeze_clips.R](../scripts/freeze_clips.R) writes one root,
`work/neon/frozen_2021`:

- `population.csv` and `population_stems.csv`: every plot with its
  geometry, core counts and population membership, and the scored core stems
  of each population.
- `<SITE>/<plot>/<rung>/`: one cell per plot and rung (native, 8, 4, 2 and
  1 points/m²), holding the raw clip with ground, the height-normalized clip,
  a 1 m TIN DTM and a JSON manifest. The clip is the nominal core plus 25 m.
- `clip_manifest.csv`: one row per cell with its status, seed, densities and
  the SHA-256 of all four files. Its presence seals the root.
- `frozen_record.json`: the freeze contract (sites, populations, rungs,
  buffer, seed salt, lidR threads, point order, package versions, input and
  code checksums), the SHA-256 of the three tables and the plot list of every
  population. Its copy is tracked as
  [frozen-clip-record.json](../docs/frozen-clip-record.json), so the declared
  population and the manifest digest are under version control.

| Site | Plot type | `adopted` plots | Native all returns per m², median (range) | Native first returns per m², median (range) | Plots below 8 first returns |
| --- | --- | --- | --- | --- | --- |
| SJER | tower | 6 | 16.6 (9.8–21.4) | 9.6 (6.4–13.2) | 2 |
| SOAP | tower | 7 | 16.6 (13.8–21.5) | 11.8 (8.5–16.0) | 0 |
| SOAP | distributed | 11 | 20.3 (10.1–22.0) | 12.6 (7.8–14.7) | 2 |
| TEAK | tower | 6 | 22.4 (16.8–24.1) | 13.4 (10.2–14.7) | 0 |
| TEAK | distributed | 13 | 17.6 (12.7–25.3) | 11.6 (7.7–17.8) | 2 |
| WREF | tower | 20 | 17.7 (10.2–25.8) | 9.0 (5.3–15.2) | 3 |
| WREF | distributed | 18 | 17.0 (9.3–23.1) | 8.1 (5.2–11.5) | 7 |
| ABBY | tower | 13 | 18.0 (10.7–21.3) | 9.8 (6.6–11.5) | 2 |
| ABBY | distributed | 12 | 19.9 (13.6–26.2) | 10.5 (8.2–12.3) | 0 |

The root holds 775 cells for 155 plots, 0.68 GB. All 773 decimated and native
cells are usable; the 8 points/m² rung of SJER_022 and SJER_054 (native 7.3
and 6.6 all returns per m²) is recorded as upsampled and not written.
Decimated cells keep 5–15% more than the target density, because a 5 m cell
holding fewer points than the target keeps them all. Eighteen of the 106
adopted plots fall below 8 first returns per m² at native density and take
the sub-8 smoothing branch there; seven of them are WREF distributed plots,
whose density the preflight could not measure from its header tiles.

The canonical root was frozen at commit `e737ff7`. Its clip manifest has
SHA-256 `4567a247a6dd6d9630d6cea5427da3e262b1dcaac4a07a1173b3764e8a63c8d4`,
the population table `f1abbee1…0dad04` and the stem table `e7de5071…2a9bfb`.
lidR 4.3.2, rlas 1.9.2 and terra 1.8.29 under R 4.3.3 produced it.

Decimation is lidR `homogenize` at 5 m cells, seeded per site, plot and rung
with the same FNV-1a key the model benchmark already used. Three fixes make
the seeded clip reproducible byte for byte:

- **One lidR thread.** The TIN normalization of a dense native clip changes
  by up to 1.2 cm between thread counts (1, 2 and 4 threads agree; 8 and 16
  give another result; 32 a third), so the provider runs lidR single-threaded.
- **A canonical point order.** Repeated reads of the same tile region return
  `gpstime` one unit in the last place apart about one read in six. A clip
  ordered by `gpstime` then changes order, and seeded sampling, which picks
  points by position, keeps a different subset. The provider snaps
  coordinates to the LAS grid, rounds `gpstime` to the microsecond and sorts
  by `gpstime`, return number and X, Y, Z before decimating. Twenty-five
  consecutive reads gave identical clips, and eleven independent freezes
  gave byte-identical native cells. Time order first keeps the LAZ files
  about 40% smaller than a purely spatial order.
- **Fresh worker processes.** Forked workers inherit the parent's GDAL and
  PROJ state; see the next section.

## Two defects found on the way

**A CRS check rejected SOAP and TEAK.** Their 2021 tiles spell the WKT unit
`"Meter"`. The coordinate guard added for the eastern preflight compared units
case-sensitively, so no SOAP or TEAK arm could build its LiDAR catalog. The
unit check is now case-insensitive.

**Forked lasR runs failed at random.** `run_sweep.R` and eleven other arms ran
lasR inside forked `mclapply` workers. In a 16-way stress test on one clip,
2–5% of runs failed with GeoPackage creation, raster-read or JSON-parse
errors; resetting PROJ inside each child did not help, while sequential runs
and fresh PSOCK workers never failed (0 of 240). The arms caught the error and
dropped the cell. The historical CHM-VWF sweep lost 5 of its 1,483 grid rows
this way, including TEAK_046 at native density in the headline
configuration, so its TEAK native headline pools 19 plots and 353 stems
instead of 20 and 396. lasR arms now map plots with `plot_lapply()`, which
uses fresh worker processes, and `run_sweep.R` stops on a detector error
instead of skipping the cell.

lasR detection is also not fully repeatable on identical bytes: on one SJER
native clip, single-threaded and sequential, 12 of 20 runs returned 115 tops
and 8 returned 116, the extra one a 4.5 m apex. This is detector noise, not
clip noise; the acceptance check measures it separately.

## Acceptance check

The acceptance test regenerates the CHM-VWF ladder (`run_sweep.R`,
4 m tolerance) on the frozen clips for the historical D17 population
(`POP=all_mapped`, 46 plots, 699 stems) and compares it with the cached June
sweep. Decimation noise is measured, not assumed: ten more roots with
`SEED_SALT=1` to `10` give ten independent seeded realizations of every
decimated cell, and with the canonical root eleven in all. The cached value is
treated as one more draw: z = (cached − mean) / (SD × √(1 + 1/11)), judged
against Student's t with 10 degrees of freedom. The rule was fixed before the
last run: every plot and stem identical across runs; native rows within 0.01
or the 99% prediction bound; every decimated cell within the 99% bound,
|z| ≤ 3.17. [check_frozen_ladder.R](../scripts/check_frozen_ladder.R) applies
it to the cells all runs share; the cached sweep lacks 5 grid rows (see
above), so the TEAK native headline row pools 19 plots.

Headline configuration (CHM 0.5 m, VWF slope 0.10), F1:

| Site | Rung | Plots / stems | Cached | Seeded mean ± SD (11 draws) | z |
| --- | --- | --- | --- | --- | --- |
| SJER | native | 8 / 71 | 0.307 | 0.311 ± 0.004 | — |
| SJER | 8 | 7 / 65 | 0.384 | 0.362 ± 0.018 | 1.1 |
| SJER | 4 | 8 / 71 | 0.383 | 0.370 ± 0.013 | 1.0 |
| SJER | 2 | 8 / 71 | 0.370 | 0.358 ± 0.021 | 0.6 |
| SJER | 1 | 8 / 71 | 0.346 | 0.366 ± 0.028 | −0.7 |
| SOAP | native | 18 / 232 | 0.398 | 0.398 ± 0.000 | — |
| SOAP | 8 | 18 / 232 | 0.361 | 0.373 ± 0.012 | −0.9 |
| SOAP | 4 | 18 / 232 | 0.424 | 0.384 ± 0.013 | **2.9** |
| SOAP | 2 | 18 / 232 | 0.393 | 0.397 ± 0.011 | −0.3 |
| SOAP | 1 | 18 / 232 | 0.398 | 0.389 ± 0.014 | 0.6 |
| TEAK | native | 19 / 353 | 0.380 | 0.380 ± 0.000 | — |
| TEAK | 8 | 20 / 396 | 0.328 | 0.325 ± 0.013 | 0.2 |
| TEAK | 4 | 20 / 396 | 0.326 | 0.322 ± 0.005 | 0.8 |
| TEAK | 2 | 20 / 396 | 0.293 | 0.310 ± 0.009 | −1.7 |
| TEAK | 1 | 20 / 396 | 0.307 | 0.306 ± 0.013 | 0.0 |

- **Reference.** Every run scores the same plots with the same stems at every
  rung.
- **Native.** Native clips are not decimated, and the eleven roots hold
  byte-identical native cells. SOAP and TEAK native rows equal the cached ones
  exactly; SJER differs by 0.004 F1, which is lasR's run-to-run jitter on one
  plot (SJER_052), the only native spread across the eleven runs.
- **Decimated.** Eleven of twelve cells pass. SOAP at 4 points/m² does not:
  recall z 2.3, precision z 3.7, F1 z 2.9. The D17 pooled 4 points/m² row
  inherits it (F1 z 3.1). The pre-registered verdict is therefore FAIL on
  one cell.
- **That cell is a tail draw of the old pipeline.** Ten more draws through
  the legacy path itself ([check_legacy_cell.R](../scripts/check_legacy_cell.R):
  unseeded `prepare_clip`, clip read order, default lidR threads) give F1
  0.388 ± 0.013, range 0.372–0.410; the eleven seeded draws give
  0.384 ± 0.013. The two pipelines agree to 0.004. The cached 0.424 lies
  above all 21 draws, about 2.8 standard deviations out; across 12 cells, one
  such draw is expected roughly one time in six. The gap is spread over most
  of the 18 plots, about 7 true positives in all, not concentrated in one.
- **Consequence for the density-ladder study.** SOAP's F1 at 4 points/m²
  there (0.42, a small peak in an otherwise flat ladder) is an upper-tail
  realization; the expected value is about 0.38–0.39, level with the other
  rungs. The flat-F1 reading is unchanged; the peak is not a finding.

The `multichm` ladder also ran on the frozen clips (`POP=all_mapped`) with
every cell complete. Its native F1 equals the cached run exactly at all three
sites (0.347, 0.439, 0.415); decimated rungs differ from the single cached
realization by −0.04 to +0.04, the same order as the CHM-VWF noise above. The
adopted population ran end to end through `run_sweep.R` at all five sites.

## How arms read the root

- `frozen_scope(d, site, A, gt)` returns the root, the plots of the
  requested population (`POP=`, default `adopted`) and the gated reference.
  `FROZEN_ROOT=` selects another root.
- `frozen_clip(NULL, site, plot, rung, ...)` on a sealed root reads one cell
  without any catalog. It checks the requested geometry against the
  manifest and every file against its SHA-256, returns `NULL` for upsampled
  or unusable cells, and stops on any mismatch. Arms never decimate, clip
  tiles or write inside the root.
- Arms that persist instance clouds or detection caches stamp the directory
  with the SHA-256 of the clip manifest; arms that read another arm's
  directory refuse one without the current stamp. Directories made on the
  historical clips therefore have to be moved aside or regenerated, never
  mixed in. SegmentAnyTree's resumable results file is tied to its root and
  population the same way.
- Crown-diameter arms keep their own gate, at least six gated stems with a
  field crown diameter, as a sub-population of the declared plots.
- The historical caches under `work/neon/<SITE>/frozen` are left untouched.
  They predate the coordinate contract and are refused by the provider.

## Reproduce

```sh
export CLAUDE_JOB_DIR=$(pwd)/work
# ground truth and tiles for every site, as in the preflight
Rscript scripts/freeze_clips.R CORES=16
# decimation-noise replicates of the historical D17 population
for k in 1 2 3 4 5 6 7 8 9 10; do
  Rscript scripts/freeze_clips.R SITES=SJER,SOAP,TEAK POPULATIONS=all_mapped \
    SEED_SALT=$k OUT=$CLAUDE_JOB_DIR/neon/frozen_2021_noise/salt_$k CORES=16
done
for S in SJER SOAP TEAK; do
  Rscript scripts/run_sweep.R SITE=$S POP=all_mapped CORES=16 TOL=4 \
    OUT=$CLAUDE_JOB_DIR/neon/$S/sweep_results_frozen_all_mapped.csv
  for k in 1 2 3 4 5 6 7 8 9 10; do
    R=$CLAUDE_JOB_DIR/neon/frozen_2021_noise/salt_$k
    Rscript scripts/run_sweep.R SITE=$S POP=all_mapped CORES=16 TOL=4 \
      FROZEN_ROOT=$R OUT=$R/${S}_sweep_results.csv
  done
done
Rscript scripts/check_frozen_ladder.R
```

The check compares against the historical `sweep_results.csv` of each D17
site. A new freeze must go to a new `OUT=`; a sealed root refuses to be
written again.

## Caveats

- **Frozen bytes, not regenerated bytes, are the reference.** Regeneration
  on this machine is byte-identical (eleven independent freezes gave the same
  native cells, and repeated decimation the same rung cells). Another lidR,
  rlas or terra version, or another platform, may still change the TIN
  normalization or the DTM at the centimetre level; the archived root and its
  manifest are what later steps verify.
- **lasR detection jitters on identical input.** On one SJER native clip, 12
  of 20 sequential single-threaded runs returned 115 tops and 8 returned 116
  (an extra 4.5 m apex). Frozen clips remove clip noise, not this detector
  noise; it is small (0.004 F1 at SJER native) but nonzero.
- **Historical artifacts were made on other clips.** The June per-site
  caches under `work/neon/<SITE>/frozen` and the instance directories of the
  model arms predate this root. Arms refuse to mix them in; re-running an
  arm writes a fresh, stamped output, and later steps should use a separate
  job directory so the historical outputs stay readable.
- **Precision is still all-plot precision.** The populations fix which plots
  and stems are scored, not the census footprint; precision inside sampled
  subplots is a separate step.
- **The six-stem gate is a whole-plot count.** A plot can pass it with fewer
  than six stems inside its core, as in the historical sweep.
