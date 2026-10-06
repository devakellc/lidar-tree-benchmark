#!/usr/bin/env bash
# Stages the reproduction archive of the frozen-root NEON benchmark: the sealed
# frozen clips and populations (the 2021 root and the QL2-rung root), every
# arm's per-cell results and persisted detections, the census-support bundles,
# the sparse-epoch roots, the June artifacts the adapter comparison re-scores
# and the native 3DEP clouds of the QL2 cross-check. The layout mirrors the
# work directory, so reproduce_paper_tables.sh runs the paper's commands
# unchanged on a copy. Symlinked inputs are copied; each job directory's
# frozen-root links are re-created relative to the archive.
#
# Every .rds is rewritten as plain R vectors (portable_rds.R): the NEON
# tables neonUtilities saves hold arrow string vectors, which read back empty
# where arrow is not installed.
#
# Left out: the RGB mosaics and raw NEON tiles (public NEON data, about 16 GB;
# a per-site rgb_tiles.csv keeps the tile extents the optical arms read), the
# NeonTreeEvaluation coverage-check imagery, logs, scratch figures, the
# compute-cost run's one-plot job directories, and superseded copies of re-run
# outputs.
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
# and the TreeisoNet voxel and mask-voxel sensitivity runs; and the QL2-rung
# run on its own root.
JOBS=(paper_runs paper_runs_all_mapped paper_runs_relaxed paper_runs_new_relaxed
      paper_runs_new_allmapped paper_runs_voxel0 paper_runs_maskvoxel paper_runs_ql2)
ROOTS=(frozen_2021 frozen_2021_ql2)
QL2_SITES=(SJER SOAP TEAK)
SPARSE=(sparse_2017 sparse_2018 sparse_compare_2021)
EXCL=(--exclude=/neon/frozen_2021 --exclude=/neon/frozen_2021_ql2 --exclude=rgb/ --exclude=lidar/ --exclude=figs/
      --exclude=chain/ --exclude=.rumdl_cache/ --exclude=sjer_header_check/ --exclude=nte/
      --exclude='*.log' --exclude='*.nohup' --exclude='*.progress'
      --exclude='master_tables.*/' --exclude='*.prev' --exclude='*.oldcrop-*'
      --exclude='*.before_persist' --exclude='*.7arm_*' --exclude='*.classical_*'
      --exclude='*_strict_v1/' --exclude='*_ladder_ff3d/' --exclude='*.crash-*'
      --exclude='*-stale' --exclude=compute_cost/jobs/ --exclude=compute_cost/logs/)

say() { echo "$(date '+%F %T') $*"; }
mkdir -p "$OUT/neon"

for r in "${ROOTS[@]}"; do
  [ -f "$WORK/neon/$r/clip_manifest.csv" ] || { echo "no sealed root $WORK/neon/$r" >&2; exit 1; }
  say "sealed root $r"
  rsync -a "$WORK/neon/$r/" "$OUT/neon/$r/"
done

say "native 3DEP clouds (QL2 cross-check)"
# The cached per-plot pulls with their provenance sidecars, the EPT candidate
# list and the EPT's recorded SRS, so the cross-check re-scores them offline.
for s in "${QL2_SITES[@]}"; do
  mkdir -p "$OUT/neon/$s/ql2"
  rsync -a --include='*.laz' --include='*.laz.json' --include='ept_candidates.csv' \
    --include='ept_srs.json' --exclude='*' "$WORK/neon/$s/ql2/" "$OUT/neon/$s/ql2/"
done

say "June artifacts (adapter before/after)"
# (June crown rows exist for SOAP only, the site of the June treeOff arm.)
for s in "${JUNE_SITES[@]}"; do
  mkdir -p "$OUT/neon/$s"
  for f in forestformer3d_instances treeisonet_results.csv treeisonet_crown_metrics.csv; do
    [ ! -e "$WORK/neon/$s/$f" ] || rsync -aL "$WORK/neon/$s/$f" "$OUT/neon/$s/"
  done
done

for j in "${JOBS[@]}" "${SPARSE[@]}"; do
  [ -d "$WORK/$j" ] || { echo "missing job directory $WORK/$j" >&2; exit 1; }
  say "job $j"
  rsync -aL "${EXCL[@]}" "$WORK/$j/" "$OUT/$j/"
  for r in "${ROOTS[@]}"; do
    [ ! -e "$WORK/$j/neon/$r" ] || ln -s "../../neon/$r" "$OUT/$j/neon/$r"
  done
done

say "RGB tile extents"
for j in "${JOBS[@]}"; do
  for s in "${SITES[@]}"; do
    nd="$WORK/$j/neon/$s"
    [ -d "$nd/rgb" ] || continue
    Rscript -e "source('$REPO/scripts/coverage_lib.R'); write_rgb_tile_index('$nd', '$OUT/$j/neon/$s/rgb_tiles.csv')"
  done
done

say "portable .rds files (no arrow vectors)"
Rscript "$REPO/scripts/portable_rds.R" "$OUT"

cp "$REPO/docs/model-provenance.json" "$OUT/model-provenance.json"
cp "$REPO/docs/reproduction-archive.md" "$OUT/README.md"
git -C "$REPO" rev-parse HEAD > "$OUT/CODE_COMMIT"

say "checksums"
(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | sort -z |
   xargs -0 sha256sum > SHA256SUMS)
say "staged $(wc -l < "$OUT/SHA256SUMS") files, $(du -sh "$OUT" | cut -f1) in $OUT"
