# Reproduction archive

This archive holds everything needed to rebuild the tables of the NEON
frozen-clip benchmark without repeating detector inference: the sealed frozen
clips and plot populations, every arm's per-cell results and persisted
detections, the census-support bundles, the native sparse-epoch roots, and the
June 2026 artifacts that the adapter comparison re-scores. The code is the
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

## Layout

The layout mirrors the benchmark's working directory, so the commands in the
study reports run unchanged with `CLAUDE_JOB_DIR` pointing into a copy.

| Path | Contents |
|---|---|
| `neon/frozen_2021/` | Sealed frozen clips (five density rungs per plot), `clip_manifest.csv` with the SHA-256 of every clip, `population.csv` and `population_stems.csv` |
| `neon/<SITE>/` | June 2026 ForestFormer3D clouds and TreeisoNet rows (SJER, SOAP, TEAK), re-scored by the adapter comparison |
| `paper_runs/` | Headline population (`adopted`): per-site field stems, plot centroids, every arm's results and persisted detections or instance clouds, optical box caches, RGB tile extents, census-support bundles and scores, master tables |
| `paper_runs_all_mapped/`, `paper_runs_relaxed/` | Sensitivity populations on the same root |
| `paper_runs_new_relaxed/`, `paper_runs_new_allmapped/` | Learned-arm runs on the plots only the sensitivity populations hold |
| `paper_runs_voxel0/`, `paper_runs_maskvoxel/` | TreeisoNet voxel and mask-voxel sensitivity runs |
| `sparse_2017/`, `sparse_2018/`, `sparse_compare_2021/` | Native sparse-epoch frozen roots, their arm results, and the matched 2021 comparison |
| `model-provenance.json` | Checkpoint hashes, image IDs and source commits of the learned arms; R environment |
| `CODE_COMMIT` | Repository commit the archive was staged with |
| `SHA256SUMS` | SHA-256 of every file |

Each job directory links `neon/frozen_2021` to the archive's sealed root.

## Not included

- NEON RGB camera mosaics and raw LiDAR tiles: public NEON data under CC0,
  about 16 GB. The frozen clips replace the LiDAR tiles. `rgb_tiles.csv`
  replaces the mosaics for the optical arms, which only read tile extents
  when scoring their cached boxes.
- Model weights and images: third-party licences. `model-provenance.json`
  gives their sources and hashes.
- FGI-EMIT data (CC BY-NC-SA 4.0) and the historical studies outside the
  frozen-root benchmark.
- Logs, figures and superseded copies of re-run outputs.

## Licence

The data in this archive are derived from NEON data products released under
CC0 1.0, and are released under CC0 1.0. The code is MIT-licensed in the
repository.
