#!/usr/bin/env bash
# Rebuilds every table of the frozen-root NEON benchmark from the reproduction
# archive (stage_archive.sh), on CPU, with no inference and no downloads. The
# archive is verified against its SHA256SUMS and copied to OUT; every output
# the steps below rebuild is deleted from the copy; the steps run in
# dependency order with the commands of the study reports; and
# compare_reproduction.R checks each rebuilt table against the archived one.
#
# Steps: learned arms re-scored on the sensitivity populations; censused
# precision (headline and strict declarations); best-configuration treetops
# and credited F1; instance IoU/PQ (and the TreeisoNet mask-voxel run); fusion;
# crown diameters; the sparse-epoch report; the adapter before/after
# comparison; the master tables of the three populations.
#
# Detector inference is not repeated: the archive holds every arm's per-cell
# results and persisted detections, which these steps re-score. The classical
# CHM detectors do re-run inside the treetop export, coverage-gap ladder and
# crown steps.
#
#   bash scripts/reproduce_paper_tables.sh ARCHIVE=<archive dir> OUT=<new dir> \
#     [CORES=8] [VERIFY=1]
#
# Run from a clone at the archive's CODE_COMMIT or later. Needs R 4.3.3 with
# the packages of reproduce/Dockerfile; runs in about an hour on 8 cores.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE=""; OUT=""; CORES=8; VERIFY=1
for a in "$@"; do
  case "$a" in
    ARCHIVE=*) ARCHIVE="${a#ARCHIVE=}" ;;
    OUT=*) OUT="${a#OUT=}" ;;
    CORES=*) CORES="${a#CORES=}" ;;
    VERIFY=*) VERIFY="${a#VERIFY=}" ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done
[ -n "$ARCHIVE" ] && [ -n "$OUT" ] || { echo "ARCHIVE= and OUT= are required" >&2; exit 2; }
[ -f "$ARCHIVE/SHA256SUMS" ] || { echo "no SHA256SUMS in $ARCHIVE" >&2; exit 1; }
[ ! -e "$OUT" ] || { echo "OUT exists: $OUT (use a new directory)" >&2; exit 2; }
ARCHIVE="$(cd "$ARCHIVE" && pwd)"

SITES=SJER,SOAP,TEAK,WREF,ABBY
SITE_LIST=(SJER SOAP TEAK WREF ABBY)
LEARNED=(forestformer3d treeisonet segmentanytree sam2point)
say() { echo "$(date '+%F %T') $*"; }
run() {  # job dir, log name, script and arguments
  local job="$1" log="$2"; shift 2
  say "START $log"
  if ! (cd "$REPO" && CLAUDE_JOB_DIR="$job" Rscript "$@") > "$LOGS/$log.log" 2>&1; then
    say "FAIL  $log (see $LOGS/$log.log)"; exit 1
  fi
  say "DONE  $log"
}

if [ "$VERIFY" = 1 ]; then
  say "verifying archive checksums"
  (cd "$ARCHIVE" && sha256sum --quiet -c SHA256SUMS)
fi
say "copying archive to $OUT"
mkdir -p "$(dirname "$OUT")"
cp -a "$ARCHIVE" "$OUT"
W="$(cd "$OUT" && pwd)"; LOGS="$W/reproduction_logs"; mkdir -p "$LOGS"
P="$W/paper_runs"; N="$P/neon"

## Outputs the steps rebuild: removed first, so nothing is carried over.
REBUILT=(
  paper_runs/master_tables paper_runs_all_mapped/master_tables paper_runs_relaxed/master_tables
  paper_runs/census_support_scores paper_runs/census_support_scores_strict
  paper_runs/neon/best_treetops_geojson paper_runs/neon/crown_compare_tables.md
  paper_runs/neon/adapter_before_after sparse_2018/compare_report
)
for s in "${SITE_LIST[@]}"; do
  for f in best_treetop_cache coverage_gap.csv instance_iou_pq.csv fusion_results.csv \
           fusion_rgb_summary.csv crown_metrics_results.csv crown_metrics_3d_results.csv \
           segmentanytree_crown_metrics.csv forestformer3d_crown_metrics.csv; do
    REBUILT+=("paper_runs/neon/$s/$f")
  done
  REBUILT+=("paper_runs_maskvoxel/neon/$s/instance_iou_pq.csv")
  for pop in all_mapped relaxed; do
    for arm in "${LEARNED[@]}"; do
      REBUILT+=("paper_runs_$pop/neon/$s/${arm}_results.csv" "paper_runs_$pop/neon/$s/${arm}_results.csv.frozen")
    done
  done
done
# Re-detected treetop caches are intermediate: compared, never failing.
printf '%s\n' "${REBUILT[@]}" | sed -E 's#^(.*best_treetop(_cache|s_geojson))$#~\1#' \
  > "$LOGS/rebuilt_paths.txt"
for r in "${REBUILT[@]}"; do rm -rf "${W:?}/$r"; done

## 1. Learned arms on the sensitivity populations, from persisted detections.
# SegmentAnyTree never completed one relaxed cell (SJER_004 at 1 point/m²);
# the rescore lists it and the master tables keep that arm pending there.
for pop in all_mapped relaxed; do
  run "$W/paper_runs_$pop" "rescore_$pop" scripts/rescore_population.R POP=$pop \
    SOURCES="$P,$W/paper_runs_new_relaxed,$W/paper_runs_new_allmapped" ALLOW_MISSING=1
done

## 2. Precision inside censused subplots: headline and strict declarations.
O="$P/census_support_scores"; OS="$P/census_support_scores_strict"
for rule in nearest exact; do
  D="docs/census-support-declaration-$rule.json"; DS="docs/census-support-declaration-$rule-strict.json"
  run "$P" "census_${rule}_ladder" scripts/score_census_support.R DECLARATION="$D" \
    ARMS=chm_vwf,lmfauto,multichm,ptrees,ams3d,forestformer3d,treeisonet,segmentanytree \
    OUT="$O/${rule}_ladder"
  run "$P" "census_${rule}_native" scripts/score_census_support.R DECLARATION="$D" \
    ARMS=chm_vwf,ptrees,ams3d,li2012 RUNGS=native OUT="$O/${rule}_native"
  run "$P" "census_strict_${rule}_ladder" scripts/score_census_support.R DECLARATION="$DS" \
    ARMS=chm_vwf,lmfauto,multichm,ptrees,ams3d OUT="$OS/${rule}_ladder"
  run "$P" "census_strict_${rule}_native" scripts/score_census_support.R DECLARATION="$DS" \
    ARMS=chm_vwf,ptrees,ams3d,li2012 RUNGS=native OUT="$OS/${rule}_native"
done
DS="docs/census-support-declaration-nearest-strict.json"
for set in "deep chm_vwf,forestformer3d,treeisonet" "ff3d chm_vwf,forestformer3d" \
           "sat chm_vwf,segmentanytree"; do
  read -r tag arms <<< "$set"
  run "$P" "census_strict_nearest_native_$tag" scripts/score_census_support.R \
    DECLARATION="$DS" ARMS="$arms" RUNGS=native OUT="$OS/nearest_native_$tag"
done

## 3. Best-configuration treetops, then credited F1 with the CHM-VWF ladder.
run "$P" export_best_treetops scripts/export_best_treetops_geojson.R SITES=$SITES
run "$P" coverage_gap scripts/coverage_gap.R SITES=$SITES CORES="$CORES" LADDER=1

## 4. Instance IoU/PQ, headline and TreeisoNet mask-voxel sensitivity.
run "$P" instance_iou scripts/score_instances_iou.R SITES=$SITES RUNGS=native,8,4,2,1 \
  APEX_PROXY=0 CORES="$CORES"
run "$W/paper_runs_maskvoxel" instance_iou_maskvoxel scripts/score_instances_iou.R \
  SITES=$SITES RUNGS=native,8,4,2,1 APEX_PROXY=0 CORES="$CORES"

## 5. Cross-arm fusion over the full ladder.
run "$P" fusion scripts/fuse_detectors.R SITES=$SITES RUNGS=native,8,4,2,1 CORES="$CORES"

## 6. Crown diameters: CHM, 3-D and deep instance segmenters, then the tables.
run "$P" crown_chm scripts/crown_metrics_sweep.R SITES=$SITES CORES="$CORES"
run "$P" crown_3d scripts/crown_metrics_3d.R SITES=$SITES CORES="$CORES"
run "$P" crown_deep scripts/crown_metrics_deepmodel.R SITES=$SITES CORES="$CORES"
run "$P" crown_analysis scripts/analyze_crown_metrics.R SITES=$SITES

## 7. Native sparse epochs against the matched 2021 rungs.
run "$W" sparse_report scripts/compare_sparse_epoch.R MODE=report \
  EPOCHS="SJER:$W/sparse_2017:2017,SOAP:$W/sparse_2018:2018,TEAK:$W/sparse_2018:2018" \
  C21="$W/sparse_compare_2021" OUT="$W/sparse_2018/compare_report"

## 8. Corrected adapters against the June artifacts.
run "$P" adapter_before_after scripts/compare_adapter_reruns.R BEFORE="$W" AFTER="$P" \
  VOXEL0="$W/paper_runs_voxel0"

## 9. Master tables: headline and the two sensitivity populations.
run "$P" master_tables scripts/master_tables.R
for pop in all_mapped relaxed; do
  run "$W/paper_runs_$pop" "master_tables_$pop" scripts/master_tables.R POP=$pop
done

## 10. Every rebuilt output against the archived copy.
say "comparing with the archive"
(cd "$REPO" && Rscript scripts/compare_reproduction.R ARCHIVE="$ARCHIVE" OUT="$W" \
   PATHS="$LOGS/rebuilt_paths.txt" REPORT="$W/reproduction_report.csv")
