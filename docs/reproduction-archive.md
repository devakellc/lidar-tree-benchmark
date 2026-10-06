# Reproduction archive

This archive holds everything needed to rebuild the tables of the NEON
frozen-clip benchmark without repeating detector inference: the sealed frozen
clips and plot populations (the 2021 root and the QL2-rung root), every arm's
per-cell results and persisted detections, the census-support bundles, the
native sparse-epoch roots, the June 2026 artifacts that the adapter comparison
re-scores, and the native 3DEP clouds of the QL2 cross-check. The code is the
[lidar-tree-benchmark repository](https://github.com/devakellc/lidar-tree-benchmark)
at the commit in `CODE_COMMIT`.

## Rebuild the tables

From a clone of the repository at `CODE_COMMIT`, with the environment of
`reproduce/Dockerfile` (R 4.3.3 with pinned lidR, lasR and geometry
packages):

```sh
docker build -t lidar-tree-benchmark-reproduce reproduce
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/repo:ro \
  -v /path/to/archive:/archive:ro -v /path/to/scratch:/out \
  lidar-tree-benchmark-reproduce \
  bash scripts/reproduce_paper_tables.sh ARCHIVE=/archive OUT=/out/run CORES=8
```

The script verifies `SHA256SUMS`, copies the archive, deletes every output it
rebuilds, runs the scoring and table steps in dependency order, and compares
each rebuilt file with the archived one. It writes
`reproduction_report.csv` and exits non-zero on any difference. It takes
about an hour on 8 cores and needs no GPU, network or NEON token.

Counts, rates and text must match exactly. Lengths in metres (coordinates,
apex heights, diameters and their errors) may differ by up to 1 cm: lasR's
canopy-model maxima vary by about a millimetre from run to run, even
single-threaded, which moves apex heights and height errors without changing
a detection or a match. Summed crown overlaps measured on the canopy model
(`iou_sum_*` in the fusion tables) inherit that noise and may differ by up to
0.01. The report marks such files `length` and gives the largest difference.
The treetop caches the export step re-detects are intermediate: lasR can
break a tie between equal canopy maxima differently in another build, moving
one apex by a cell, so differences there are reported as `intermediate` and
do not fail the run; the tables built from them are held to the rules above.
The native QL2 cross-check's per-plot rows and their pooled table are
intermediate too: on the dense 3DEP clouds (30–65 pulses/m²) lasR moves apex
heights by a few centimetres between runs and can break a canopy-maximum tie
differently in another build (one detection at one SOAP plot in the clean
container). The paired table the report cites reads only the decimated rows
and is strict. The figure images are intermediate; the numbers
each figure plots are in its strict CSV.

## Last rebuild

The archive was staged on 5 October 2026 from commit `da13583` (36,250
files, 5.5 GB) and rebuilt the same day in the clean container on CPU with
8 cores, in 55 minutes, exit status 0. Of the 1,221 rebuilt files, 1,207 were
byte-identical, 2 equal within 1e-8, 2 within the length and overlap
allowances (SJER: height RMSE 1.2 mm, summed crown IoU 0.0026), 7 were the
figure images and 3 the native QL2 cross-check's intermediate rows, and none
differed, was missing or extra. That run's `reproduction_report.csv` was not
kept; the deposit run keeps its report and log tail beside the archive.

## Layout

The layout mirrors the benchmark's working directory, so the commands in the
study reports run unchanged with `CLAUDE_JOB_DIR` pointing into a copy.

| Path | Contents |
|---|---|
| `neon/frozen_2021/` | Sealed frozen clips (five density rungs per plot), `clip_manifest.csv` with the SHA-256 of every clip, `population.csv` and `population_stems.csv` |
| `neon/frozen_2021_ql2/` | Sealed QL2-rung root: the same population and native clips with one seeded rung at 3.2 points/m² (about 2 pulses/m²), and its manifest |
| `neon/<SITE>/` | June 2026 ForestFormer3D clouds and TreeisoNet rows (SJER, SOAP, TEAK), re-scored by the adapter comparison |
| `neon/<SITE>/ql2/` | Native USGS 3DEP clouds over the plots (SJER, SOAP, TEAK) with their provenance sidecars, the EPT candidates and the EPT's recorded SRS, read by the QL2 cross-check |
| `paper_runs/` | Headline population (`adopted`): per-site field stems, plot centroids, every arm's results and persisted detections or instance clouds, optical box caches, RGB tile extents, census-support bundles and scores, master tables, scoring sensitivities, the paper's figures with the numbers each plots |
| `paper_runs_ql2/` | Every full-ladder arm on the QL2 rung, with its census bundle and scores |
| `paper_runs_all_mapped/`, `paper_runs_relaxed/` | Sensitivity populations on the same root |
| `paper_runs_new_relaxed/`, `paper_runs_new_allmapped/` | Learned-arm runs on the plots only the sensitivity populations hold |
| `paper_runs_voxel0/`, `paper_runs_maskvoxel/` | TreeisoNet voxel and mask-voxel sensitivity runs |
| `sparse_2017/`, `sparse_2018/`, `sparse_compare_2021/` | Native sparse-epoch frozen roots, their arm results, and the matched 2021 comparison |
| `model-provenance.json` | Checkpoint hashes, image IDs and source commits of the learned arms; R environment |
| `CODE_COMMIT` | Repository commit the archive was staged with |
| `SHA256SUMS` | SHA-256 of every file |

Each job directory links `neon/frozen_2021` to the archive's sealed root;
`paper_runs_ql2` links `neon/frozen_2021_ql2` instead.

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

## Licence

The data in this archive are derived from NEON data products released under
CC0 1.0 and from USGS 3DEP point clouds in the public domain, and are released
under CC0 1.0. The code is MIT-licensed in the
repository.
