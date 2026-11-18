# Reproduction archive

This archive holds everything needed to rebuild the tables of the NEON
frozen-clip benchmark without repeating detector inference: the sealed frozen
clips and plot populations (the 2021 root and the QL2-rung root), every arm's
per-cell results and persisted detections, the census-support bundles, the
native sparse-epoch roots, the June 2026 artifacts that the adapter comparison
re-scores, and the native 3DEP clouds of the QL2 cross-check. The code is the
[lidar-tree-benchmark
repository](https://github.com/devakellc/lidar-tree-benchmark) at the commit in
`CODE_COMMIT`.

## Rebuild the tables

From a clone of the repository at `CODE_COMMIT`, with the environment of
`reproduce/Dockerfile` (R 4.3.3 with pinned lidR, lasR and geometry packages):

```sh
docker build -t lidar-tree-benchmark-reproduce reproduce
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/repo:ro \
  -v /path/to/archive:/archive:ro -v /path/to/scratch:/out \
  lidar-tree-benchmark-reproduce \
  bash scripts/reproduce_paper_tables.sh ARCHIVE=/archive OUT=/out/run CORES=8
```

The script verifies `SHA256SUMS`, copies the archive, deletes every output it
rebuilds, runs the scoring and table steps in dependency order, and compares
each rebuilt file with the archived one. It writes `reproduction_report.csv` and
exits non-zero on any difference. It needs no GPU, network or NEON token. The
steps of the October rebuild took about an hour on 8 cores; with the steps added
on 17 November 2026 (below) the test rebuild took about three hours on 8
cores, about 50 minutes of them for the chance null inside censused subplots
and 50 for the chance-correction simulation. Rebuild from
`CODE_COMMIT` itself: two contract files (`core_density_contract.json` and
`routing_contract.json`) record checksums of the scripts that wrote them, so a
later commit that changes those scripts fails their comparison although every
table matches.

Counts, rates and text must match exactly. Lengths in metres (coordinates, apex
heights, diameters and their errors) may differ by up to 1 cm: lasR's
canopy-model maxima vary by about a millimetre from run to run, even
single-threaded, which moves apex heights and height errors without changing a
detection or a match. Summed crown overlaps measured on the canopy model
(`iou_sum_*` in the fusion tables) inherit that noise and may differ by up to
0.01. The report marks such files `length` and gives the largest difference. The
treetop caches the export step re-detects are intermediate: lasR can break a tie
between equal canopy maxima differently in another build, moving one apex by a
cell, so differences there are reported as `intermediate` and do not fail the
run; the tables built from them are held to the rules above. The native QL2
cross-check's per-plot rows and their pooled table are intermediate too: on the
dense 3DEP clouds (medians of 42 and 29 pulses/m² at SOAP and TEAK) lasR moves
apex heights by a few centimetres between runs and can break a canopy-maximum
tie differently in another build (one detection at one SOAP plot in the clean
container). The paired table the report cites reads only the decimated rows and
is strict. The figure images are intermediate; the numbers each figure plots are
in its strict CSV.

## Last rebuild

The archive was staged on 5 October 2026 from commit `da13583` (36,250
files, 5.5 GB). It was rebuilt in the clean container on CPU with 8 cores on
5 October (55 minutes; 1,207 of 1,221 files byte-identical, 2 equal within
1e-8, 2 within the length and overlap allowances, 7 figure images and 3
native QL2 cross-check rows intermediate, none differing) and again on
6 October with the report kept: 55 minutes, exit status 0, 1,204 files
byte-identical, 2 equal within 1e-8, 2 within the allowances (SJER: height
RMSE 1.2 mm, summed crown IoU 0.0026), 13 intermediate (the 7 figure images,
the native QL2 cross-check's per-plot and pooled rows, two re-detected
treetop caches and the treetop export they feed, all lasR tie-break or
millimetre height differences), and none differing, missing or extra. The
6 October `reproduction_report.csv` and console log are kept beside the
archive under `work/zenodo/reproduction_2026-10-06/`, and the deposit run
keeps its own.

## Added since the last rebuild

The archive of 5 October does not hold the outputs of the steps added later,
and no staged archive has yet been rebuilt with them. The next staging and
rebuild must cover:

- from October: the chance-agreement null with its seed and minimum-shift
  checks, the leave-out and chance-corrected rank correlations, the baseline
  smoothing sensitivity, the instance audit, the density-routed pipeline and
  the redrawn figures;
- from the revision of 17 November 2026: the density of the scored plot cores
  and the routing banded by it (the whole-clip banding kept as a sensitivity),
  the unsmoothed baseline at the QL2 rung (`paper_runs_nosmooth_ql2/`) and the
  chance null of both unsmoothed runs, the chance null inside censused
  subplots (over the declared and the unsmoothed baseline) and on plot
  subsets, the chance-correction simulation with the clustering of the
  reference stems, the native QL2 cross-check with
  noise-class and withheld points removed, the count of noise-class points in
  the frozen clips, the reference and fire audit, and the figures redrawn on
  core densities;
- from 18 November 2026: the split-crown diagnostic
  (`paper_runs/sensitivity/split_crowns/`), which re-reads the persisted
  native-density detections, and Figure 2 redrawn as the evaluation protocol
  alone.

Three points differ from the October run. The two runs of the baseline without
its smoothing are re-scored from their archived detections and not re-detected,
because lasR's canopy-model maxima change by one tree top in a few cells from
run to run (measured in the repository's
`results/baseline-smoothing-sensitivity-results.md`). The reference audit runs
offline from the perimeter responses archived in
`paper_runs/reference_audit/fire_cache/`. And dated backups of re-run outputs
(names holding `.YYYY-MM-DD`) are left out of the archive.

A test of 17 November 2026, which staged a copy of the work directory and
rebuilt it on the development machine (not in the clean container), rebuilt
1,470 files: 1,424 byte-identical, 25 equal within the declared tolerances, 15
intermediate, and 6 that differed. Those six were put right in the work
directory and the code before the next staging. The matcher sensitivity's lead
table had been written before the code added its rows of lead changes. The
QL2 rung's matcher grid and chance null are written in the order of the run's
detector list, which differed from the rebuild script's, so the routing
contracts, which record those files' checksums, differed too. These were
regenerated with the script's own commands; their values are unchanged. The
script for the chance-corrected rank correlations paired detectors by their
position in two files, so with the rebuild's order it paired two detectors
wrongly at the QL2 rung; it now pairs each detector with itself, and the
archived correlations, computed from files in matching order, are unchanged.
The sixth file was the simulation's settings record, which then held its run
time.

A second test, staged from the finished branch on the evening of 17 November
2026 after these repairs and after the simulation's split-crown detectors and
the reference-stem clustering were added, rebuilt 1,483 files: 1,462
byte-identical, 7 equal within the declared tolerances, 14 intermediate, and
none differing, missing or extra. The intermediate files are the figures'
PDFs, two cached CHM-VWF tree-top files, and the native QL2 cross-check's
detection results, whose counts move by a tree or two between runs. The
split-crown diagnostic was added to the rebuild script the next day; run
separately against that staged copy and against the work directory, with one
core and with eight, it wrote byte-identical outputs, but no staged archive
yet holds them.

## Layout

The layout mirrors the benchmark's working directory, so the commands in the
study reports run unchanged with `CLAUDE_JOB_DIR` pointing into a copy.

| Path | Contents |
|---|---|
| `neon/frozen_2021/` | Sealed frozen clips (five density rungs per plot), `clip_manifest.csv` with the SHA-256 of every clip, `population.csv` and `population_stems.csv` |
| `neon/frozen_2021_ql2/` | Sealed QL2-rung root: the same population and native clips with one seeded rung at 3.2 points/m² (about 2 pulses/m²), and its manifest |
| `neon/<SITE>/` | June 2026 ForestFormer3D clouds and TreeisoNet rows (SJER, SOAP, TEAK), re-scored by the adapter comparison |
| `neon/<SITE>/ql2/` | Native USGS 3DEP clouds over the plots (SJER, SOAP, TEAK) with their provenance sidecars, the EPT candidates and the EPT's recorded SRS, read by the QL2 cross-check |
| `paper_runs/` | Headline population (`adopted`): per-site field stems, plot centroids, every arm's results and persisted detections or instance clouds, optical box caches, RGB tile extents, census-support bundles and scores, master tables, scoring sensitivities (with the censused null, the plot-subset null and the chance-correction simulation), core densities, the density routing, the reference audit with its cached fire perimeters, the paper's figures with the numbers each plots |
| `paper_runs_ql2/` | Every full-ladder arm on the QL2 rung, with its census bundle and scores |
| `paper_runs_nosmooth/`, `paper_runs_nosmooth_ql2/` | CHM-VWF run with its sub-8 pulses/m² smoothing disabled, on the 2021 root and on the QL2-rung root, with its chance null and censused scores: the baseline smoothing sensitivity |
| `paper_runs_all_mapped/`, `paper_runs_relaxed/` | Sensitivity populations on the same root |
| `paper_runs_new_relaxed/`, `paper_runs_new_allmapped/` | Learned-arm runs on the plots only the sensitivity populations hold |
| `paper_runs_voxel0/`, `paper_runs_maskvoxel/` | TreeisoNet voxel and mask-voxel sensitivity runs |
| `sparse_2017/`, `sparse_2018/`, `sparse_compare_2021/` | Native sparse-epoch frozen roots, their arm results, and the matched 2021 comparison |
| `model-provenance.json` | Checkpoint hashes, image IDs and source commits of the learned arms; R environment |
| `CODE_COMMIT` | Repository commit the archive was staged with |
| `SHA256SUMS` | SHA-256 of every file |

Each job directory links `neon/frozen_2021` to the archive's sealed root;
`paper_runs_ql2` and `paper_runs_nosmooth_ql2` link `neon/frozen_2021_ql2`
instead.

## Not included

- NEON RGB camera mosaics and raw LiDAR tiles: public NEON data under CC0,
  about 16 GB. The frozen clips replace the LiDAR tiles. `rgb_tiles.csv`
  replaces the mosaics for the optical arms, which only read tile extents
  when scoring their cached boxes.
- Model weights and images: third-party licences. `model-provenance.json`
  gives their sources and hashes.
- FGI-EMIT data (CC BY-NC-SA 4.0) and the historical studies outside the
  frozen-root benchmark.
- Logs, scratch figures and superseded copies of re-run outputs.
- Runs added after the tables were fixed: the SegmentAnyTree grouping-radius
  check of Section S18 of the supplement and the ForestMamba arm of Section
  S23. Their reports in the repository,
  `results/segmentanytree-radius-results.md` and
  `results/forestmamba-results.md`, give the commands that regenerate them
  with a GPU.

## Licence

The data in this archive are derived from NEON data products released under
CC0 1.0 and from USGS 3DEP point clouds in the public domain, and are released
under CC0 1.0. The code is MIT-licensed in the
repository.
