#!/usr/bin/env bash
# #I5 mirror: fetch model weights/images into a local store and verify SHA256
# against a VERSIONED manifest (gpu/CHECKSUMS.sha256). First run records the
# full hash; later runs hard-fail on any mismatch (manual verify against the
# manifest -- the store layout is not `sha256sum -c`-shaped). GitHub-release
# assets go through authenticated `gh` (the unauthenticated github.com download
# path 504s here); other sources use curl.
#
# Usage:
#   bash gpu/mirror_weights.sh              # TreeisoNet only (the #M7 detection arm)
#   bash gpu/mirror_weights.sh ALL          # + SegmentAnyTree (#M6) + ForestFormer3D (#M8)
#                                           #   + ForestMamba
#   bash gpu/mirror_weights.sh FORESTMAMBA  # the ForestMamba checkpoint only
set -euo pipefail
WHICH="${1:-treeisonet}"
HERE="$(cd "$(dirname "$0")" && pwd)"
STORE="$HERE/store"; MAN="$HERE/CHECKSUMS.sha256"
mkdir -p "$STORE/treeaibox" "$STORE/segmentanytree" "$STORE/forestformer3d" "$STORE/forestmamba"
touch "$MAN"
verify() {  # dest sha_prefix(sanity; "" to skip)
  local dest="$1" pre="$2" base got exp
  base="$(basename "$dest")"; got="$(sha256sum "$dest" | cut -d' ' -f1)"
  if [ -n "$pre" ]; then case "$got" in "$pre"*) : ;;
    *) echo "FAIL prefix $base: $got !~ $pre"; exit 1;; esac; fi
  if grep -q "  $base\$" "$MAN"; then
    exp="$(grep "  $base\$" "$MAN" | cut -d' ' -f1)"
    [ "$got" = "$exp" ] || { echo "FAIL manifest $base: $got != $exp"; exit 1; }
  else echo "$got  $base" >> "$MAN"; fi
  echo "OK $base ($got)"
}
gh_get() {  # asset dest sha_prefix  (TreeAIBox release asset via authenticated gh)
  local asset="$1" dest="$2" dir; dir="$(dirname "$dest")"
  if [ ! -f "$dest" ]; then echo "GET $asset"
    gh release download v1.0 --repo NRCan/TreeAIBox --pattern "$asset" --dir "$dir" --clobber
    [ "$dir/$asset" = "$dest" ] || mv "$dir/$asset" "$dest"
  fi
  verify "$dest" "$3"
}
url_get() {  # url dest sha_prefix  (curl for non-release sources)
  local url="$1" dest="$2"
  [ -f "$dest" ] || { echo "GET $(basename "$dest")"; curl -fL --retry 3 "$url" -o "$dest"; }
  verify "$dest" "$3"
}
gdrive_get() {  # file_id dest sha_prefix  (public Google Drive file)
  # Large files answer with a virus-scan form; its uuid confirms the download.
  # The file only takes its final name once its hash is the pinned one, so an
  # interrupted or HTML answer never blocks a later run.
  local id="$1" dest="$2" base="https://drive.usercontent.google.com/download" uuid got exp
  if [ ! -f "$dest" ]; then echo "GET $(basename "$dest")"
    uuid="$(curl -fsSL "$base?id=$id&export=download" | grep -o 'name="uuid" value="[^"]*"' |
            sed 's/.*value="//; s/"$//' || true)"
    if ! curl -fL --retry 3 "$base?id=$id&export=download&confirm=t${uuid:+&uuid=$uuid}" \
         -o "$dest.part"; then rm -f "$dest.part"; echo "FAIL download $(basename "$dest")"; exit 1; fi
    got="$(sha256sum "$dest.part" | cut -d' ' -f1)"
    exp="$(grep "  $(basename "$dest")\$" "$MAN" | cut -d' ' -f1 || true)"   # unpinned: empty
    if [ -z "$exp" ] || [ "$got" != "$exp" ]; then
      rm -f "$dest.part"; echo "FAIL manifest $(basename "$dest"): $got != ${exp:-unpinned}"; exit 1
    fi
    mv "$dest.part" "$dest"
  fi
  verify "$dest" "$3"
}
# --- TreeisoNet ALS (the #M7 detection arm; fetched unless only ForestMamba is asked) ---
if [ "$WHICH" != "FORESTMAMBA" ]; then
  gh_get "treeisonet_als_reclamation_treeloc_esegformer3D_128_10cm_GPU4GB.pth" \
         "$STORE/treeaibox/als_treeloc.pth" c6e15a21
  gh_get "treeisonet_als_reclamation_treeoff_esegformer3D_128_10cm_GPU4GB.pth" \
         "$STORE/treeaibox/als_treeoff.pth" 6cf5d890
fi
if [ "$WHICH" = "ALL" ]; then
  url_get "https://media.githubusercontent.com/media/SmartForest-no/SegmentAnyTree/main/model_file/PointGroup-PAPER.pt" \
          "$STORE/segmentanytree/PointGroup-PAPER.pt" 0b4d74b4
  url_get "https://zenodo.org/api/records/16742708/files/clean_forestformer.zip/content" \
          "$STORE/forestformer3d/clean_forestformer.zip" ""
fi
# --- ForestMamba v6 release checkpoint (the authors' Google Drive folder
# 1wf_IcXNIZgxOg_Dkrt45ph2ssdBeWCHm); its SHA-256 must match the manifest ---
if [ "$WHICH" = "ALL" ] || [ "$WHICH" = "FORESTMAMBA" ]; then
  gdrive_get 1XJ__eeYUDLbdaj77f_ryxydIs3FiTQaT "$STORE/forestmamba/v6_epoch_1500_fix.pth" a398d6e5
fi
echo "manifest -> $MAN"; cat "$MAN"
# NOTE: TreeisoNet config JSONs are copied from the cloned repo in
# gpu/setup_treeisonet_env.sh (upstream names vary in punctuation -> glob).
# The SegmentAnyTree Docker image is pulled in #M6.
