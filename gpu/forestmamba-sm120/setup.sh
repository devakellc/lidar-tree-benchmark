#!/usr/bin/env bash
# ForestMamba arm setup: the pinned upstream checkout and the SHA-256-verified
# release checkpoint under gpu/store/forestmamba, then the inference image.
# Needs the ForestFormer3D image (tag ff3d-sm120, gpu/forestformer3d-sm120).
#   bash gpu/forestmamba-sm120/setup.sh [IMAGE=forestmamba-sm120]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; GPU="$(dirname "$HERE")"
IMAGE="forestmamba-sm120"
for a in "$@"; do
  case "$a" in IMAGE=*) IMAGE="${a#IMAGE=}" ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;; esac
done
REPO="$GPU/store/forestmamba/ForestMamba"
REF="$(grep -v '^#' "$GPU/ForestMamba.commit" | head -1)"
mkdir -p "$(dirname "$REPO")"
[ -d "$REPO/.git" ] || git clone --quiet https://github.com/thanhhff/ForestMamba.git "$REPO"
git -C "$REPO" checkout --quiet "$REF"
[ "$(git -C "$REPO" rev-parse HEAD)" = "$REF" ] || { echo "checkout is not $REF" >&2; exit 1; }
bash "$GPU/mirror_weights.sh" FORESTMAMBA       # -> gpu/store/forestmamba/v6_epoch_1500_fix.pth
BASE_ID="sha256:fd60f5cdc5ae880af13b339f4aa1f1e891a3809c7f39fb15d2b5ff04978799f3"
got="$(docker image inspect ff3d-sm120 --format '{{.Id}}' 2>/dev/null)" ||
  { echo "build ff3d-sm120 first (gpu/forestformer3d-sm120)" >&2; exit 1; }
[ "$got" = "$BASE_ID" ] || echo "warning: ff3d-sm120 is $got, not the benchmark's base $BASE_ID" >&2
docker build --build-arg FM_REF="$REF" -t "$IMAGE" "$HERE"
docker run --rm --entrypoint pip "$IMAGE" freeze > "$HERE/fm_freeze.txt.new"
cmp -s "$HERE/fm_freeze.txt.new" "$HERE/fm_freeze.txt" && rm "$HERE/fm_freeze.txt.new" ||
  echo "warning: the image's packages differ from fm_freeze.txt; see fm_freeze.txt.new" >&2
echo "ForestMamba $REF + checkpoint ready; image $IMAGE"
