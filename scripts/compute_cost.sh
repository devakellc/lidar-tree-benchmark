#!/usr/bin/env bash
# Compute cost per arm on a fixed subset: one tower and one distributed plot
# per site (the first of each type in the adopted population), native density.
# The classical arms run their detector alone on each cell
# (compute_cost_cell.R; detection seconds in-process). The learned and RGB
# arms run their own sweep on a scratch job directory that holds only that
# plot, so the wall time includes model load and container start, as in the
# paper runs. Every call is wrapped in /usr/bin/time (wall, peak host RSS); a
# poller samples nvidia-smi for the peak device memory above the idle level.
# Run it with the GPU otherwise idle and the CPU quiet, one call at a time.
#   bash scripts/compute_cost.sh OUT=<new dir> [WORK=work] [ARMS=...] [SITES=...]
# Writes <OUT>/compute_cost_cells.csv and <OUT>/compute_cost.md.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$REPO/work"; OUT=""; SITES="SJER SOAP TEAK WREF ABBY"
ARMS="chm_vwf multichm lmfauto ptrees ams3d li2012 forestformer3d treeisonet segmentanytree sam2point deepforest detectree2"
for a in "$@"; do
  case "$a" in
    OUT=*) OUT="${a#OUT=}" ;; WORK=*) WORK="${a#WORK=}" ;;
    ARMS=*) ARMS="${a#ARMS=}"; ARMS="${ARMS//,/ }" ;; SITES=*) SITES="${a#SITES=}"; SITES="${SITES//,/ }" ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done
[ -n "$OUT" ] || { echo "OUT= is required" >&2; exit 2; }
WORK="$(cd "$WORK" && pwd)"; ROOT="$WORK/neon/frozen_2021"; PR="$WORK/paper_runs"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"; LOG="$OUT/logs"; mkdir -p "$LOG"
CSV="$OUT/compute_cost_cells.csv"
echo "arm,site,plot,exit,wall_s,detect_s,max_rss_kib,gpu_peak_mib,points" > "$CSV"
cd "$REPO"

# The subset: first tower and first distributed adopted plot per site.
CELLS=$(Rscript -e "p <- read.csv('$ROOT/population.csv'); p <- p[p\$in_adopted, ]; p <- p[order(p\$site, p\$plotID), ];
  for (s in strsplit('$SITES', ' ')[[1]]) for (t in c('tower', 'distributed')) {
    x <- p[p\$site == s & p\$plotType == t, ]; if (nrow(x)) cat(s, x\$plotID[1], '\n') }")

gpu_used() { nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1; }
IDLE=$(gpu_used)

# A job directory holding one plot: its stems and centroid only, with the
# site's vst and RGB linked and the sealed root.
one_plot_job() {  # site plot -> prints the job dir
  local s=$1 p=$2 j="$OUT/jobs/$1_$2"
  mkdir -p "$j/neon/$s"
  ln -sfn "$ROOT" "$j/neon/frozen_2021"
  for f in vst rgb; do [ -e "$PR/neon/$s/$f" ] && ln -sfn "$(readlink -f "$PR/neon/$s/$f")" "$j/neon/$s/$f"; done
  Rscript -e "g <- read.csv('$PR/neon/$s/ground_truth_stems.csv'); write.csv(g[g\$plotID == '$p', ], '$j/neon/$s/ground_truth_stems.csv', row.names = FALSE)
    c <- read.csv('$PR/neon/$s/plot_centroids.csv'); write.csv(c[c\$plotID == '$p', ], '$j/neon/$s/plot_centroids.csv', row.names = FALSE)"
  echo "$j"
}

timed() {  # arm site plot logfile command... -> appends a CSV row
  local arm=$1 s=$2 p=$3 lf=$4; shift 4
  local peak="$OUT/.gpu_peak"; echo "$IDLE" > "$peak"
  ( while :; do u=$(gpu_used); [ "$u" -gt "$(cat "$peak")" ] && echo "$u" > "$peak"; sleep 0.5; done ) &
  local poller=$!
  /usr/bin/time -f "TIME,%e,%M,%x" -o "$lf.time" "$@" > "$lf" 2>&1
  kill $poller 2>/dev/null; wait $poller 2>/dev/null
  local t; t=$(tail -1 "$lf.time")
  local cost; cost=$(tr '\r' '\n' < "$lf" | grep "^COST," | tail -1)
  local det=""; local pts=""
  [ -n "$cost" ] && det=$(echo "$cost" | cut -d, -f6) && pts=$(echo "$cost" | cut -d, -f5)
  local rc; rc=$(echo "$t" | cut -d, -f4)
  echo "$arm,$s,$p,$rc,$(echo "$t" | cut -d, -f2),$det,$(echo "$t" | cut -d, -f3),$(( $(cat "$peak") - IDLE )),$pts" >> "$CSV"
  echo "$(date '+%T') $arm $s $p exit=$rc wall=$(echo "$t" | cut -d, -f2)s"
}

while read -r S P; do
  [ -n "$S" ] || continue
  J=""
  for arm in $ARMS; do
    lf="$LOG/${arm}_${S}_${P}.log"
    case "$arm" in
      chm_vwf|multichm|lmfauto|ptrees|ams3d|li2012)
        CLAUDE_JOB_DIR=$PR timed "$arm" "$S" "$P" "$lf" Rscript scripts/compute_cost_cell.R ARM=$arm SITE=$S PLOT=$P ;;
      *)
        [ -n "$J" ] || J=$(one_plot_job "$S" "$P")
        export CLAUDE_JOB_DIR="$J"
        case "$arm" in
          forestformer3d) timed "$arm" "$S" "$P" "$lf" Rscript scripts/detect_forestformer3d_sweep.R \
                            SITE=$S POP=adopted RUNGS=native TIMEOUT=3600 ;;
          treeisonet)     timed "$arm" "$S" "$P" "$lf" Rscript scripts/detect_treeisonet_sweep.R \
                            SITE=$S POP=adopted RUNGS=native VOXEL=0.8,0.8,2.0 MASK_VOXEL=0 ;;
          segmentanytree) timed "$arm" "$S" "$P" "$lf" Rscript scripts/detect_segmentanytree_sweep.R \
                            SITE=$S POP=adopted RUNGS=native CORES=1 ;;
          sam2point)      timed "$arm" "$S" "$P" "$lf" Rscript scripts/detect_sam2point_sweep.R \
                            SITE=$S POP=adopted MAXPROMPTS=40 ;;
          deepforest)     timed "$arm" "$S" "$P" "$lf" Rscript scripts/detect_deepforest_sweep.R \
                            SITE=$S POP=adopted ;;
          detectree2)     timed "$arm" "$S" "$P" "$lf" Rscript scripts/detect_detectree2_sweep.R \
                            SITE=$S POP=adopted PLOTS=$P ;;
        esac
        unset CLAUDE_JOB_DIR ;;
    esac
  done
done <<< "$CELLS"

# Failed calls (non-zero exit) are listed and left out of the summary.
Rscript -e "x <- read.csv('$CSV'); bad <- x[x\$exit != 0, ]
  if (nrow(bad)) { cat('failed calls (not summarised):\\n'); print(bad[, c('arm', 'site', 'plot', 'exit')], row.names = FALSE) }
  x <- x[x\$exit == 0, ]; arms <- unique(x\$arm)
  r <- do.call(rbind, lapply(arms, function(a) { y <- x[x\$arm == a, ]
    data.frame(arm = a, cells = nrow(y), total_wall_s = sum(y\$wall_s), median_cell_wall_s = median(y\$wall_s),
               max_cell_wall_s = max(y\$wall_s), median_detect_s = if (all(is.na(y\$detect_s))) NA else median(y\$detect_s, na.rm = TRUE),
               max_rss_mib = max(y\$max_rss_kib) / 1024, max_gpu_mib = max(y\$gpu_peak_mib)) }))
  write.csv(r, '$OUT/compute_cost.csv', row.names = FALSE)
  f <- function(v, k = 1) ifelse(is.na(v), '—', formatC(v, format = 'f', digits = k))
  writeLines(c('| Arm | Cells | Total wall, s | Median cell wall, s | Maximum cell wall, s | Median detection, s | Peak host RSS, MiB | Peak GPU memory, MiB |',
               '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
               sprintf('| %s | %d | %s | %s | %s | %s | %s | %s |', r\$arm, r\$cells, f(r\$total_wall_s), f(r\$median_cell_wall_s),
                       f(r\$max_cell_wall_s), f(r\$median_detect_s, 2), f(r\$max_rss_mib, 0), f(r\$max_gpu_mib, 0))),
             '$OUT/compute_cost.md')"
cat "$OUT/compute_cost.md"
