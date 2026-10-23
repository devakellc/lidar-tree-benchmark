#!/usr/bin/env bash
# Run the jobs of the SegmentAnyTree radius check (scripts/sat_radius_check.R
# MODE=prep writes OUT/jobs.tsv): one container per job, at most PARALLEL at
# once (default 4; SegmentAnyTree needs about 2.3 CPU cores and 1 GB of GPU
# memory per container). The driver, the compatibility shims and the clip are
# copied into the container and the instance LAS copied out, so no host
# directory is mounted. A job with a radius passes it as SAT_CLUSTER_RADIUS and
# must log the override, or its output is set aside as .unverified. Jobs with
# an output are skipped, so an interrupted run resumes.
#   bash gpu/run_sat_radius_check.sh OUT [PARALLEL] [JOB...]
# IMAGE (default sat-sm120-test) names the SegmentAnyTree image.
set -u
OUT=${1:?usage: run_sat_radius_check.sh OUT [PARALLEL] [JOB...]}
P=${2:-4}
shift; [ $# -gt 0 ] && shift
GPU_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IMAGE=${IMAGE:-sat-sm120-test}
[ -f "$OUT/jobs.tsv" ] || { echo "no $OUT/jobs.tsv; run sat_radius_check.R MODE=prep" >&2; exit 1; }
mkdir -p "$OUT/out" "$OUT/logs"

run_job() {
  local job=$1 ply=$2 radius=${3:-}
  local out="$OUT/out/$job.las" log="$OUT/logs/$job.log" stage cid rc t0
  local envs=()
  if [ -s "$out" ]; then echo "skip $job"; return 0; fi
  stage=$(mktemp -d "$OUT/stage_XXXXXX")
  mkdir -p "$stage/gpu/sat_compat" "$stage/in" "$stage/out"
  cp "$GPU_DIR/run_segmentanytree.py" "$stage/gpu/"
  cp "$GPU_DIR/sat_compat/usercustomize.py" "$stage/gpu/sat_compat/"
  cp "$ply" "$stage/in/clip.ply"
  [ -n "$radius" ] && envs=(-e "SAT_CLUSTER_RADIUS=$radius")
  t0=$(date +%s)
  cid=$(docker create --gpus all --network none --shm-size=8g --ipc=host "${envs[@]}" \
        "$IMAGE" python3 /pilot/gpu/run_segmentanytree.py /pilot/in/clip.ply /pilot/out/clip.las) || {
    echo "FAIL $job create"; rm -rf "$stage"; return 1; }
  docker cp "$stage/." "$cid:/pilot" > /dev/null
  docker start -a "$cid" > "$log" 2>&1; rc=$?
  docker cp "$cid:/pilot/out/clip.las" "$out" > /dev/null 2>&1
  docker rm "$cid" > /dev/null; rm -rf "$stage"
  if [ "$rc" -ne 0 ] || [ ! -s "$out" ]; then echo "FAIL $job rc=$rc"; rm -f "$out"; return 1; fi
  if [ -n "$radius" ] && ! grep -q "sat_compat: region_grow radius" "$log"; then
    mv "$out" "$out.unverified"; echo "FAIL $job override not logged"; return 1
  fi
  echo "done $job $(( $(date +%s) - t0 ))s"
}
export -f run_job; export OUT GPU_DIR IMAGE

if [ $# -gt 0 ]; then
  for j in "$@"; do awk -F'\t' -v j="$j" '$1 == j' "$OUT/jobs.tsv"; done
else
  tail -n +2 "$OUT/jobs.tsv"
fi | xargs -P "$P" -d '\n' -n 1 bash -c 'IFS=$'"'"'\t'"'"' read -r a b c <<< "$1"; run_job "$a" "$b" "$c"' _ |
  tee -a "$OUT/progress.log"
