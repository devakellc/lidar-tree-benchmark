#!/usr/bin/env bash
# Rebuilds every table of the frozen-root NEON benchmark from the reproduction
# archive (stage_archive.sh), on CPU, with no inference and no downloads. The
# archive is verified against its SHA256SUMS and copied to OUT; every output
# the steps below rebuild is deleted from the copy; the steps run in
# dependency order with the commands of the study reports; and
# compare_reproduction.R checks each rebuilt table against the archived one.
#
# Steps: learned arms re-scored on the sensitivity populations; censused
# precision (headline and strict declarations, and the QL2 rung); best-
# configuration treetops and credited F1; instance IoU/PQ (and the TreeisoNet
# mask-voxel run); fusion; crown diameters; the sparse-epoch report; the
# adapter before/after comparison; the master tables of the three populations
# (the headline with the QL2 rung); the scoring sensitivities (matcher,
# exact-2021 references, stem-position jitter, chance agreement), the density
# of the scored plot cores, the density-routed pipeline banded by it, the
# unsmoothed baseline's chance null, the chance null inside censused subplots
# and on plot subsets, the chance-correction simulation, the split-crown
# diagnostic, the calibration/validation split, the matching-rule ranks, the
# native QL2 cross-check, the count of noise-class points in the clips and the
# reference audit; the figures.
#
# Detector inference is not repeated: the archive holds every arm's per-cell
# results and persisted detections, which these steps re-score; that includes
# the two runs of the baseline without its smoothing. The classical CHM
# detectors do re-run inside the treetop export, coverage-gap ladder, fusion
# and crown steps, and on the archived native 3DEP clouds in the QL2
# cross-check.
#
#   bash scripts/reproduce_paper_tables.sh ARCHIVE=<archive dir> OUT=<new dir> \
#     [CORES=8] [VERIFY=1]
#
# Run from a clone at the archive's CODE_COMMIT: core_density_contract.json,
# routing_contract.json and the master tables' master_contract.json record
# checksums of the code that wrote them, so a later commit works only if it
# leaves that code unchanged. Needs R 4.3.3 with the packages of
# reproduce/Dockerfile; runs in about three hours on 8 cores (about 50 minutes
# each for the chance null inside censused subplots and the chance-correction
# simulation).
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
  paper_runs_ql2/census_support_scores paper_runs_ql2/sensitivity
  paper_runs_nosmooth/sensitivity paper_runs_nosmooth_ql2/sensitivity
  paper_runs_nosmooth/census_support_scores paper_runs_nosmooth_ql2/census_support_scores
  paper_runs/sensitivity/null_corrected_rank.csv
  paper_runs/core_density paper_runs/density_routing_clip
  paper_runs/neon/clip_noise_audit.csv paper_runs/neon/clip_noise_audit_summary.csv
  paper_runs/neon/best_treetops_geojson paper_runs/neon/crown_compare_tables.md
  paper_runs/neon/adapter_before_after sparse_2018/compare_report
  paper_runs/sensitivity paper_runs/neon/native_ql2_vs_decimated.csv
  paper_runs/neon/native_ql2_paired.csv paper_runs/density_routing
)
# The reference audit's tables and log; its cache of perimeter responses is
# archived input.
for f in reference_records reference_summary reference_years plot_measurement_years \
         fire_sources fire_queries fire_perimeters fire_source_hits fire_hits fire_near_plots \
         fire_source_offsets fire_field_remarks fire_status_transitions fire_status_individuals; do
  REBUILT+=("paper_runs/reference_audit/$f.csv")
done
REBUILT+=(paper_runs/reference_audit/reference_audit_log.txt)
# The nine figures, each as PNG and PDF, and the numbers each plots (the
# schematic, figure 2, plots none).
for n in 1 2 3 4 5 6 7 s1 s2; do
  REBUILT+=("paper_runs/figures/figure_$n.png" "paper_runs/figures/figure_$n.pdf")
  [ "$n" = 2 ] || REBUILT+=("paper_runs/figures/figure_$n.csv")
done
for s in SJER SOAP TEAK; do REBUILT+=("paper_runs/neon/$s/ql2/ql2_detect_results.csv"); done
for s in "${SITE_LIST[@]}"; do
  for f in best_treetop_cache coverage_gap.csv instance_iou_pq.csv fusion_results.csv \
           fusion_rgb_summary.csv crown_metrics_results.csv crown_metrics_3d_results.csv \
           segmentanytree_crown_metrics.csv forestformer3d_crown_metrics.csv \
           calval_metrics.csv matching_rule_ranks.csv; do
    REBUILT+=("paper_runs/neon/$s/$f")
  done
  REBUILT+=("paper_runs_maskvoxel/neon/$s/instance_iou_pq.csv")
  for pop in all_mapped relaxed; do
    for arm in "${LEARNED[@]}"; do
      REBUILT+=("paper_runs_$pop/neon/$s/${arm}_results.csv" "paper_runs_$pop/neon/$s/${arm}_results.csv.frozen")
    done
  done
done
# Intermediate outputs are compared but never fail the run: the re-detected
# treetop caches; the native QL2 cross-check's per-plot rows and their pooled
# table, because on the dense 3DEP clouds lasR moves apex heights by a few
# centimetres between runs and can break a canopy-maximum tie differently in
# another build (the paired table the report cites reads only the decimated
# rows and is strict); and the figure images, PNG and PDF (cairo writes a
# creation date into each PDF, so its bytes change from run to run; the
# numbers each figure plots are its strict CSV).
printf '%s\n' "${REBUILT[@]}" |
  sed -E 's#^(.*(best_treetop(_cache|s_geojson)|ql2_detect_results\.csv|native_ql2_vs_decimated\.csv|\.png|\.pdf))$#~\1#' \
  > "$LOGS/rebuilt_paths.txt"
for r in "${REBUILT[@]}"; do rm -rf "${W:?}/$r"; done
# Figure 2 is a schematic with no data file. An archive staged before it
# became one holds the old Figure 2's numbers (now Figure 3's), which no step
# rebuilds or compares.
rm -f "$W/paper_runs/figures/figure_2.csv"

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
  run "$W/paper_runs_ql2" "census_${rule}_ql2" scripts/score_census_support.R DECLARATION="$D" \
    ARMS=chm_vwf,lmfauto,multichm,ptrees,ams3d,forestformer3d,treeisonet,segmentanytree \
    RUNGS=3.2 FROZEN_ROOT="$W/neon/frozen_2021_ql2" \
    OUT="$W/paper_runs_ql2/census_support_scores/${rule}_ladder"
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

## 9. Master tables: headline (with the QL2 rung's own root) and the two
## sensitivity populations.
run "$P" master_tables scripts/master_tables.R \
  RUNG_JOBS="$W/paper_runs_ql2:$W/neon/frozen_2021_ql2"
for pop in all_mapped relaxed; do
  run "$W/paper_runs_$pop" "master_tables_$pop" scripts/master_tables.R POP=$pop
done

## 10. Scoring sensitivities from persisted detections (matcher, exact-2021,
## stem jitter and the chance-agreement null), the density-routed pipeline,
## the calibration/validation split, the matching-rule ranks and the native
## QL2 cross-check.
for mode in matcher exact2021; do
  run "$P" "sensitivity_$mode" scripts/paper_sensitivity.R MODE=$mode CORES="$CORES"
done
run "$P" sensitivity_jitter scripts/paper_sensitivity.R MODE=jitter K=200 CORES="$CORES"
run "$P" sensitivity_null scripts/paper_sensitivity.R MODE=null K=200 CORES="$CORES"
run "$P" sensitivity_null_tol2 scripts/paper_sensitivity.R MODE=null TOL=2 K=200 CORES="$CORES"
# Null checks: an independent set of shifts (Monte Carlo error) and two
# other minimum shifts.
run "$P" sensitivity_null_seed1 scripts/paper_sensitivity.R MODE=null SEED=1 K=200 CORES="$CORES"
for ms in 6 12; do
  run "$P" "sensitivity_null_ms$ms" scripts/paper_sensitivity.R MODE=null MIN_SHIFT=$ms K=200 CORES="$CORES"
done
# The QL2 rung's matcher grid and null, from its own root and job directory.
QL2_ARMS=chm_vwf,lmfauto,multichm,ptrees,ams3d,forestformer3d,treeisonet,segmentanytree
for q in "matcher" "null K=200" "null TOL=2 K=200"; do
  read -r -a qa <<< "$q"
  run "$W/paper_runs_ql2" "sensitivity_ql2_${q// /_}" scripts/paper_sensitivity.R MODE="${qa[@]}" \
    RUNGS=3.2 FROZEN_ROOT="$W/neon/frozen_2021_ql2" ARMS=$QL2_ARMS CORES="$CORES"
done
# The chance-correction simulation (post hoc): synthetic plots scored with the
# paper's matcher and null; it reads nothing from the archive. Then how
# clustered the reference stems of the distributed plots are beside the
# simulated stands (reads the sealed root's population and stems, and the
# archived census-support bundles for the plots with admitted support).
run "$P" chance_simulation scripts/simulate_chance_correction.R N=200 K=200 SEED=0 CORES=6
run "$P" reference_clustering scripts/reference_stem_clustering.R N=200 SEED=0
# The split-crown diagnostic (post hoc): close pairs of every ladder arm's
# persisted native detections, the valley test on the native canopy model and
# split-crown candidates, in the nominal cores and inside the censused subplots
# (it stops unless the counts equal the arms' own results and the censused
# scores of step 2); then the same with pairs 2.5-4 m apart, beyond CHM-VWF's
# smallest half-window.
run "$P" split_crowns scripts/split_crown_diagnostic.R CORES="$CORES"
run "$P" split_crowns_rmin2.5 scripts/split_crown_diagnostic.R RMIN=2.5 CORES="$CORES" \
  OUT="$P/sensitivity/split_crowns/rmin2.5"
# First-return density inside the scored plot cores (read-only on every root),
# which names the density levels and bands the density-routed pipeline.
run "$P" core_density scripts/core_density.R RUNG_ROOTS="$W/neon/frozen_2021_ql2" \
  EPOCHS="SJER:$W/sparse_2017:2017,SOAP:$W/sparse_2018:2018,TEAK:$W/sparse_2018:2018" \
  C21="$W/sparse_compare_2021"
# The density-routed pipeline (post hoc), from the observed and null counts of
# every level, the QL2 level's from its own root; it stops unless every
# detector's per-level F1 and corrected F1 equal the master tables and nulls.
# Bands by core density; the whole-clip banding is kept as a sensitivity.
run "$P" density_routing scripts/paper_density_routing.R \
  RUNG_JOBS="$W/paper_runs_ql2:$W/neon/frozen_2021_ql2"
run "$P" density_routing_clip scripts/paper_density_routing.R DENSITY=clip \
  RUNG_JOBS="$W/paper_runs_ql2:$W/neon/frozen_2021_ql2" OUT="$P/density_routing_clip"
# The baseline without its sub-8 pulses/m² smoothing: its two runs (the sealed
# 2021 root and the QL2 rung's root, each in its own job directory) are
# re-scored from their archived detections and not re-detected, because lasR's
# canopy-model maxima change by one tree top in a few cells from run to run
# (baseline smoothing report). Their chance nulls at 4 and 2 m use the shifts
# of every other detector. Then the audit of the learned arms' persisted
# instances.
NSJ="$W/paper_runs_nosmooth"; NSQJ="$W/paper_runs_nosmooth_ql2"
for t in 4 2; do
  run "$NSJ" "nosmooth_null_tol$t" scripts/paper_sensitivity.R MODE=null K=200 TOL=$t \
    ARMS=chm_vwf CORES="$CORES"
  run "$NSQJ" "nosmooth_ql2_null_tol$t" scripts/paper_sensitivity.R MODE=null K=200 TOL=$t \
    ARMS=chm_vwf RUNGS=3.2 FROZEN_ROOT="$W/neon/frozen_2021_ql2" CORES="$CORES"
done
# Chance agreement inside the censused subplots (post hoc): the same shifts
# scored by the censused scorer, stopping unless the observed counts equal the
# census scores, the observed leads the master tables and the nominal-box null
# the null cells above; the unsmoothed baseline scored and nulled the same way
# from its persisted detections in its own job directories (no master-table
# rows, so CHECK_MASTER=0) and the leads over it; then the nominal null on plot
# subsets (tower and distributed plots, and without the three SOAP plots inside
# CAL FIRE's perimeter of the 2020 Creek Fire that were measured only before it).
DN=docs/census-support-declaration-nearest.json; SUP="$P/reference_support_census_event"
run "$NSJ" census_nosmooth scripts/score_census_support.R DECLARATION="$DN" ARMS=chm_vwf \
  SUPPORT="$SUP" OUT="$NSJ/census_support_scores/nearest_ladder"
run "$NSQJ" census_nosmooth_ql2 scripts/score_census_support.R DECLARATION="$DN" ARMS=chm_vwf \
  RUNGS=3.2 FROZEN_ROOT="$W/neon/frozen_2021_ql2" SUPPORT="$SUP" \
  OUT="$NSQJ/census_support_scores/nearest_ladder"
for t in 4 2; do
  run "$P" "census_null_tol$t" scripts/paper_census_null.R DECLARATION="$DN" TOL=$t K=200 CORES="$CORES"
  run "$W/paper_runs_ql2" "census_null_ql2_tol$t" scripts/paper_census_null.R DECLARATION="$DN" \
    RUNGS=3.2 TOL=$t FROZEN_ROOT="$W/neon/frozen_2021_ql2" ARMS=$QL2_ARMS \
    MASTER_TABLES="$P/master_tables/master_contrasts.csv" K=200 CORES="$CORES"
  run "$NSJ" "census_null_nosmooth_tol$t" scripts/paper_census_null.R DECLARATION="$DN" \
    ARMS=chm_vwf TOL=$t SUPPORT="$SUP" CHECK_MASTER=0 K=200 CORES="$CORES"
  run "$NSQJ" "census_null_nosmooth_ql2_tol$t" scripts/paper_census_null.R DECLARATION="$DN" \
    ARMS=chm_vwf RUNGS=3.2 TOL=$t FROZEN_ROOT="$W/neon/frozen_2021_ql2" SUPPORT="$SUP" \
    CHECK_MASTER=0 K=200 CORES="$CORES"
  run "$P" "census_null_unsmoothed_tol$t" scripts/paper_census_null_unsmoothed.R TOL=$t \
    JOBS="$P,$W/paper_runs_ql2" NOSMOOTH="$NSJ,$NSQJ"
done
run "$P" census_null_strict scripts/paper_census_null.R \
  DECLARATION=docs/census-support-declaration-nearest-strict.json RUNGS=native K=200 CORES="$CORES"
run "$P" null_subsets scripts/paper_null_subsets.R EXCLUDE=SOAP_002,SOAP_008,SOAP_013
run "$P" baseline_smoothing scripts/baseline_smoothing_sensitivity.R NOSMOOTH="$NSJ"
run "$P" instance_audit scripts/instance_audit.R CORES="$CORES"
run "$P" corrected_rank scripts/corrected_rank_stability.R
run "$P" calval_split scripts/calval_split.R SITES=$SITES SEED=1 FRAC=0.5 \
  SEEDS=1,2,3,4,5,6,7,8,9,10
for s in "${SITE_LIST[@]}"; do
  run "$P" "matching_rules_$s" scripts/compare_matching_rules.R SITE=$s
done
run "$P" native_ql2_crosscheck scripts/native_ql2_crosscheck.R SITES=SOAP,SJER,TEAK \
  POP=adopted CACHE_JOB="$W"
run "$P" native_ql2_paired scripts/native_ql2_paired.R
# Noise-class points in the frozen NEON clips, which no detector removes.
run "$P" clip_noise_audit scripts/clip_noise_audit.R
# The reference-population and fire-history audit (post hoc), offline from the
# archived perimeter responses.
run "$P" reference_audit scripts/reference_population_audit.R OFFLINE=1

## 11. The paper's figures.
run "$P" figures scripts/paper_figures.R

## 12. Every rebuilt output against the archived copy.
say "comparing with the archive"
(cd "$REPO" && Rscript scripts/compare_reproduction.R ARCHIVE="$ARCHIVE" OUT="$W" \
   PATHS="$LOGS/rebuilt_paths.txt" REPORT="$W/reproduction_report.csv")
