# DeepForest RGB arm + the density-invariant anchor

RGB detections stay fixed as the benchmark thins LiDAR inputs, giving DeepForest
a **density-invariant reference** for the router and fusion.
The historical standalone comparison below motivated the paired fusion study;
it does not by itself establish a routing policy. This
promotes DeepForest from "optional reference" to a scored arm: it runs the
NEON-pretrained crown model on the NEON RGB camera mosaics (DP3.30010, 2021 — the
same epoch as the LiDAR/field data), reduces each crown box to its centroid,
samples an apex Z from a CHM built on the matched frozen clip, and scores against
field stems with the same `score_plot` harness.

Regenerate:

```sh
export CLAUDE_JOB_DIR=$(pwd)/work
Rscript scripts/neon_download_aop.R SITE=SOAP YEAR=2021      # DP3.30010 RGB tiles
Rscript scripts/detect_deepforest_sweep.R SITE=SOAP          # -> deepforest_results.csv
```

DeepForest runs **CPU-only** (`~/miniconda3/envs/deepforest`, torch 2.12) — no
Blackwell GPU build needed; a 1 km² tile predicts in ~14 s
(`gpu/run_deepforest.py`, which georeferences the pixel boxes through the raster
transform). Verified on SOAP (8 tiles, 2021, 100,953 crown boxes site-wide).

## Historical standalone tables

### DeepForest (RGB) standalone — SOAP, 253 stems

| metric | value |
|---|--:|
| recall | 0.506 |
| precision | 0.289 |
| F1 | 0.368 |
| recall dominant / codominant | 0.530 / 0.537 |
| **recall understory** | **0.348** |

### Density-invariant anchor: F1 vs LiDAR density rung

| arm | native | 8 | 4 | 2 | 1 |
|---|--:|--:|--:|--:|--:|
| **deepforest (RGB, flat)** | 0.37 | 0.37 | 0.37 | 0.37 | 0.37 |
| segmentanytree | 0.46 | 0.44 | 0.44 | **0.32** | **0.12** |
| multichm | 0.44 | 0.42 | 0.45 | 0.44 | 0.46 |
| chm_vwf | 0.38 | 0.36 | 0.42 | 0.39 | 0.40 |
| forestformer3d | 0.26 | — | — | — | — |

## Historical hypotheses

- **DeepForest is the density floor every LiDAR arm is measured against.** Its F1
  is flat at 0.37 by construction (fixed-resolution RGB). SegmentAnyTree — the
  best *high*-density arm — beats it at native/8/4 (0.44–0.46) but **falls below
  it at 2 pts/m² (0.32) and collapses at 1 pt/m² (0.12)**. This motivated testing
  optical support below ~2 pts/m², not replacing all LiDAR arms at that density.
  ForestFormer3D is already below the floor at native.
- **multichm is the one LiDAR arm that stays above the optical floor at every
  rung** (0.42–0.46), consistent with the routing study's robust low-density
  default; DeepForest is the safety net for the arms that aren't.
- **RGB sees understory the 2.5-D CHM misses.** DeepForest's understory recall
  (0.348) beats CHM-VWF's (0.27): a nadir RGB detector catches canopy-gap crowns
  a surface model smooths over. This is exactly the decorrelated coverage a fusion
  member should add.
- **It pays in recall, not precision.** DeepForest over-detects (precision 0.29;
  100k boxes site-wide, many in the buffer / small understory) — so as a fusion
  member it contributes recall and the density-invariant floor, with confidence
  calibration or a score threshold needed to temper its commission.

## RGB plus LiDAR fusion

Regenerated 2026-09-15 on **18 SOAP plots, 232 core stems, all five density
rungs**. The equal-set population differs from the historical 253-stem optical
table above. DeepForest scores F1 0.457 and understory recall 0.356 on this
population at every rung. The run produced 1,872 cell/configuration rows in
`fusion_results.csv` and 40 equal-set summaries in `fusion_rgb_summary.csv`.

```sh
Rscript scripts/calibrate_confidence.R SITES=SOAP,SJER,TEAK FROM_CACHE=1
Rscript scripts/fuse_detectors.R SITE=SOAP RUNGS=native,8,4,2,1 CORES=1
# Smoke run with separate outputs:
Rscript scripts/fuse_detectors.R SITE=SOAP PLOTS=SOAP_031,SOAP_021 \
  RUNGS=native,1 CORES=1 OUT=work/fusion-rgb-smoke.csv
```

### Operating points

- `union`, `majority`, `layered`, and `k1`-`kN` are the LiDAR-only controls.
  The available members are CHM-VWF, multichm, ptrees, AMS3D, SegmentAnyTree,
  native Li2012, and ForestFormer3D where its persisted cloud exists. In this
  run there were seven LiDAR members at native and five at the sparse rungs;
  no SOAP 8-rung ForestFormer3D clouds were available.
- `rgb_union` reclusters the LiDAR and DeepForest apexes together using the
  existing 2 m horizontal / 5 m vertical gates. `rgb_agreement` retains only
  clusters containing both DeepForest and at least one LiDAR member.
- `lidar_nms` and `rgb_nms` use greedy detection-level non-maximum suppression,
  which suppresses only neighbors of a retained apex and avoids transitive
  cluster chains. LiDAR detections have priority 1; optical detections use their
  calibrated probability, with height and coordinates breaking ties.
- `rgb_weighted` requires at least 1.5 votes, fixed before the run: each LiDAR
  member contributes 1 and DeepForest contributes its calibrated probability.
  Duplicate detections from one arm contribute only their maximum weight.
  `rgb_weighted_raw` substitutes the original DeepForest score as the control.
  Full confidence weighting of every LiDAR member remains future pipeline work.

DeepForest calibration uses 303 labelled core detections and holds out the
target plot: each fusion cell uses the other 17 SOAP plots. No target-plot
labels enter its weights. Optical boxes and their native-CHM heights remain
fixed across rungs. Missing RGB coverage or missing tile predictions omit the
optical member; completed empty predictions retain a zero-detection row.
`RGB=0` disables optical modes. All summaries use shared plots per rung.

### Recall and F1

| rung | LiDAR union R | RGB union R | LiDAR union F1 | RGB union F1 | RGB agreement F1 | RGB weighted F1 |
|---|--:|--:|--:|--:|--:|--:|
| native | 0.828 | 0.789 | 0.283 | 0.278 | 0.434 | 0.403 |
| 8 | 0.866 | 0.832 | 0.353 | 0.350 | 0.466 | 0.429 |
| 4 | 0.862 | 0.845 | 0.393 | 0.390 | 0.442 | 0.477 |
| 2 | 0.815 | 0.815 | 0.438 | 0.419 | 0.460 | 0.476 |
| 1 | 0.677 | 0.741 | 0.414 | 0.406 | 0.407 | 0.463 |

### Understory and the NMS control

| rung | LiDAR union R_under | RGB union R_under | LiDAR NMS R | RGB NMS R | LiDAR NMS R_under | RGB NMS R_under |
|---|--:|--:|--:|--:|--:|--:|
| native | 0.844 | 0.844 | 0.953 | 0.957 | 0.933 | 0.933 |
| 8 | 0.844 | 0.778 | 0.901 | 0.914 | 0.844 | 0.844 |
| 4 | 0.756 | 0.711 | 0.866 | 0.879 | 0.756 | 0.756 |
| 2 | 0.689 | 0.644 | 0.836 | 0.862 | 0.689 | 0.689 |
| 1 | 0.556 | 0.578 | 0.690 | 0.767 | 0.578 | 0.622 |

At 1 pt/m2, RGB raises union recall by 0.065 and understory recall by 0.022.
With the same NMS algorithm on both sides, gains are 0.078 and 0.044. Raw F1
falls in both comparisons: more detections also increase the precision cost.
RGB does not deliver the broad understory improvement initially hypothesized.

### Calibration ablation

| rung | weighted with raw RGB score F1 | weighted with calibrated RGB score F1 |
|---|--:|--:|
| native | 0.403 | 0.403 |
| 8 | 0.429 | 0.429 |
| 4 | 0.475 | 0.477 |
| 2 | 0.475 | 0.476 |
| 1 | 0.465 | 0.463 |

Calibration changes F1 by at most 0.003 at this fixed threshold. At 1 pt/m2,
weighted RGB F1 0.463 exceeds LiDAR `k2` F1 0.450, but the raw-score RGB
control reaches 0.465: that gain cannot be attributed to calibration.

### Implications for the pipeline and router

The five-rung results support an optional optical recall contribution at the
sparsest rung. They do **not** establish a universal optical-dominant rule
below 2 pt/m2: at 2, union recall is unchanged and understory recall falls.
Reclustering can reduce recall because a new optical point bridges two LiDAR
clusters or changes their representative. NMS avoids that particular chaining
effect, but its raw F1 still decreases when RGB joins.

The summaries retain per-class counts and proxy Coverage/PQ for downstream
policy analysis. For example, 1-rung RGB union raises proxy Coverage from
0.402 to 0.422, while PQ falls from 0.118 to 0.112. These masks are
apex-Voronoi proxies, not measured crown boundaries. Native CHM heights also
mean this is not a wholly sparse-input experiment. The incomplete field map
still affects precision; co-detection within this same ensemble must not be
treated as independent confirmation of its detections. External validation
remains the next gate before choosing final routing thresholds.

## Detectree2 — a second optical detector

A meta-pipeline ensemble is only as good as its member diversity. DeepForest is
a RetinaNet box detector; **Detectree2** (Ball et al., MIT) is architecturally
different **Mask R-CNN** crown *polygon* segmenter, so its agreement with
DeepForest is a confidence signal and its polygons let the optical modality
contribute crown **width** (`d_eq`), not just detection.
`scripts/detect_detectree2_sweep.R` runs it (`gpu/run_detectree2.py`) on per-plot
RGB crops.

**The risky build is solved.** Detectron2 was the flagged unknown — it has no
Blackwell (sm_120) wheels. It builds **CPU-only against torch 2.12** (gcc 13) and
imports + runs cleanly; inference on a plot-sized crop is ~5 s, so a whole 1 km²
mosaic (~625 Mask R-CNN sub-tiles) is avoided by cropping to plots.

**But the pretrained weights transfer poorly to CA conifer** — the tested unknown,
answered. The `250312_flexi` model is tropical/temperate-trained:

| optical arm | n_ref | recall | precision | F1 | crown d_eq |
|---|--:|--:|--:|--:|--:|
| deepforest (RetinaNet, NEON-trained) | 253 | 0.506 | 0.289 | **0.368** | (boxes) |
| detectree2 (Mask R-CNN, tropical-trained) | 147 | 0.265 | 0.245 | **0.255** | 4.8 m median |

Readings:

- **Domain-matched training beats architecture.** DeepForest's NEON-trained
  RetinaNet (F1 0.368) clearly outperforms Detectree2's tropical-trained Mask R-CNN
  (0.255) on CA conifer — the transfer gap, not the detector family, dominates.
  Detectree2 under-detects (recall 0.265, ~10–14 crowns per plot core vs
  DeepForest's many), as expected when the training canopy is wrong.
- **Its value is diversity + crown width, not standalone accuracy.** The polygons
  give a usable crown-diameter product (`d_eq` median 4.8 m, IQR 4.0–6.5 m) a box
  detector cannot, and the architectural independence makes DeepForest∩Detectree2
  agreement a stronger optical confidence signal than either alone — the intended
  fusion role. A CA-conifer-fine-tuned Detectree2 would close the gap.

## Caveats

- **SOAP only, 2021 RGB.** SJER/TEAK 2021 RGB are available (the downloader is
  `SITE=`-parameterized); a full three-site run is future work.
- **Apex Z is sampled from the LiDAR CHM**, so a DeepForest box over a real gap
  with no LiDAR canopy gets the 2 m floor — a minor height-gate effect.
- **Precision is a lower bound** (the field-map coverage gap), and DeepForest's
  own over-detection compounds it; recall / understory / the density crossover are
  the trustworthy signals.
- **NEON is reprocessing DP3.30010 for RELEASE-2026**; this used the 2021
  acquisition to match the benchmark epoch (recorded in the `rgb/` path).
