#!/usr/bin/env bash
# Stages the reproduction archive of the frozen-root NEON benchmark: the sealed
# frozen clips and populations, every arm's per-cell results and persisted
# detections, the census-support bundles, the sparse-epoch roots and the June
# artifacts the adapter comparison re-scores. The layout mirrors the work
# directory, so reproduce_paper_tables.sh runs the paper's commands unchanged
# on a copy. Symlinked inputs are copied; each job directory's frozen_2021
# link is re-created relative to the archive.
#
# Left out: the RGB mosaics and raw NEON tiles (public NEON data, about 16 GB;
# a per-site rgb_tiles.csv keeps the tile extents the optical arms read), the
# NeonTreeEvaluation coverage-check imagery, logs, figures, and superseded
# copies of re-run outputs.
#
#   bash scripts/stage_archive.sh OUT=<new dir> [WORK=work]
#
# Also writes <OUT>/model-provenance.json (from docs/), <OUT>/README.md
# (from docs/reproduction-archive.md) and <OUT>/SHA256SUMS over every file.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$REPO/work"; OUT=""
for a in "$@"; do
  case "$a" in
    OUT=*) OUT="${a#OUT=}" ;;
    WORK=*) WORK="${a#WORK=}" ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done
[ -n "$OUT" ] || { echo "OUT= is required" >&2; exit 2; }
[ ! -e "$OUT" ] || { echo "OUT exists: $OUT (stage into a new directory)" >&2; exit 2; }
WORK="$(cd "$WORK" && pwd)"
[ -f "$WORK/neon/frozen_2021/clip_manifest.csv" ] || { echo "no sealed root under $WORK/neon/frozen_2021" >&2; exit 1; }

SITES=(SJER SOAP TEAK WREF ABBY)
JUNE_SITES=(SJER SOAP TEAK)
# Job directories run on the sealed 2021 root: the headline population, the
# two sensitivity populations, the new-plot runs they were re-scored from,
# and the TreeisoNet voxel and mask-voxel sensitivity runs.
JOBS=(paper_runs paper_runs_all_mapped paper_runs_relaxed paper_runs_new_relaxed
      paper_runs_new_allmapped paper_runs_voxel0 paper_runs_maskvoxel)
SPARSE=(sparse_2017 sparse_2018 sparse_compare_2021)
EXCL=(--exclude=/neon/frozen_2021 --exclude=rgb/ --exclude=lidar/ --exclude=figs/
      --exclude=chain/ --exclude=.rumdl_cache/ --exclude=sjer_header_check/ --exclude=nte/
      --exclude='*.log' --exclude='*.nohup' --exclude='*.progress'
      --exclude='master_tables.*/' --exclude='*.prev' --exclude='*.oldcrop-*'
      --exclude='*.before_persist' --exclude='*.7arm_*' --exclude='*.classical_*'
      --exclude='*_strict_v1/' --exclude='*_ladder_ff3d/' --exclude='*.crash-*'
      --exclude='*-stale')

say() { echo "$(date '+%F %T') $*"; }
mkdir -p "$OUT/neon"

say "sealed root"
rsync -a "$WORK/neon/frozen_2021/" "$OUT/neon/frozen_2021/"

say "June artifacts (adapter before/after)"
for s in "${JUNE_SITES[@]}"; do
  mkdir -p "$OUT/neon/$s"
  rsync -aL "$WORK/neon/$s/forestformer3d_instances" "$WORK/neon/$s/treeisonet_results.csv" \
    "$WORK/neon/$s/treeisonet_crown_metrics.csv" "$OUT/neon/$s/"
done

for j in "${JOBS[@]}" "${SPARSE[@]}"; do
  [ -d "$WORK/$j" ] || { echo "missing job directory $WORK/$j" >&2; exit 1; }
  say "job $j"
  rsync -aL "${EXCL[@]}" "$WORK/$j/" "$OUT/$j/"
  if [ -e "$WORK/$j/neon/frozen_2021" ]; then
    ln -s ../../neon/frozen_2021 "$OUT/$j/neon/frozen_2021"
  fi
done

say "RGB tile extents"
for j in "${JOBS[@]}"; do
  for s in "${SITES[@]}"; do
    nd="$WORK/$j/neon/$s"
    [ -d "$nd/rgb" ] || continue
    Rscript -e "source('$REPO/scripts/coverage_lib.R'); write_rgb_tile_index('$nd', '$OUT/$j/neon/$s/rgb_tiles.csv')"
  done
done

cp "$REPO/docs/model-provenance.json" "$OUT/model-provenance.json"
cp "$REPO/docs/reproduction-archive.md" "$OUT/README.md"
git -C "$REPO" rev-parse HEAD > "$OUT/CODE_COMMIT"

say "checksums"
(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | sort -z |
   xargs -0 sha256sum > SHA256SUMS)
say "staged $(wc -l < "$OUT/SHA256SUMS") files, $(du -sh "$OUT" | cut -f1) in $OUT"
