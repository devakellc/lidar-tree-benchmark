# Implementation plan

This is the design worked out before the hand-off. Nothing below is
implemented yet. Parameters marked *declared* are proposed defaults that should
be frozen in a protocol before training, not tuned on test data.

## Layout

The plan targets `agrigoriev/lidar_tree_benchmarks` conventions:

```text
scripts/naip_treetop_lib.R        pure helpers (no lasR), unit-testable
scripts/naip_treetop_labels.R     step 1 entry point (KEY=VALUE args)
tests/testthat/test-naip-treetop-lib.R
gpu/naip_treetop/                 Python package, run with PYTHONPATH=gpu
  frame.py      AOI grid, pixel <-> map transforms
  naip.py       NAIP search/read, pairing checks, co-registration
  sun.py        solar position, shadow-based azimuth estimate
  targets.py    sigma(h), Gaussian heatmaps, weight maps
  dataset.py    stacks, spatial splits, chip sampling, augmentation
  models.py     UNetSmall, DinoHeatmapNet
  losses.py     penalty-reduced focal loss with a weight map
  peaks.py      heatmap -> peaks
  evaluate.py   Hungarian matching, height-binned P/R/F1, block bootstrap
  semi.py       pseudo-positive selection
  synthetic.py  synthetic scenes for tests and CPU smoke runs
  prepare.py / train.py / predict.py / score.py   CLIs
  configs/e2_unet.json, e3_dinov3.json, e4_dinov3_sun_chmv2.json,
          e5_semi.json
tests/test_naip_treetop_*.py
docs/naip-treetop-protocol.md
results/naip-treetop-labels-results.md   step 1 histogram and floor
```

Note that `*.csv`, `*.tif`, `*.gpkg` and `work/` are gitignored in that
repository, so the AOI manifest must be JSON.

## Step 1: label pipeline (R, lasR + terra)

Inputs: an AOI manifest (`aois.json`: id, EPT name, centre lon/lat, side in
metres). Outputs per AOI under `$CLAUDE_JOB_DIR/naip_treetop/<aoi>/`:
`chm.tif`, `chm_smooth.tif`, `tops.csv`, `aoi.json`; pooled
`height_histogram.csv`, `label_height_histogram.png`, `label_floor.json`.

### Frame

- Label frame CRS: NAD83 / UTM zone of the AOI (EPSG 26910 for zone 10,
  26911 for zone 11), because NAIP is distributed in that CRS. 3DEP EPT is
  EPSG:3857 produced with a null datum shift, so the same ballpark transform
  keeps the two consistent.
- Square AOI, origin and side snapped to multiples of 1.5 m so the 0.5 m CHM
  grid and the 0.3 m NAIP grid share corners.
- Fetch a 20 m buffer around the AOI; detect on the buffered grid; keep tops
  inside the AOI only.

### EPT is Web Mercator: two corrections

Verified in [findings.md](findings.md): lasR's `summarise()` on an EPT
reports density per 3857 square unit.

- True density = reported density × k², with k = 1 / cos(latitude)
  (k² ≈ 1.75 at 41° N, 1.94 at 44° N).
- Rasterize the CHM in 3857 at `res × k` so a cell is `res` metres on the
  ground, then `terra::project()` it (bilinear) onto the UTM frame at `res`.
- Alternative input path: a UTM LAZ extracted with PDAL (`extract.json` in
  lidar_tree_benchmarks), with k = 1 and no projection. Use it where PDAL is
  available; it is the repository's metric-faithful path.

### CHM

- `reader_rectangles(..., filter = "-drop_class 7 18 -drop_withheld")`
  → `normalize()` → `triangulate(filter = keep_first())` → `rasterize()` →
  `pit_fill()`.
- Resolution: the spec asks for 0.5 m. The repository's rule is density
  first (`res >= pulse spacing`). Declared: `res = 0.5` when first-return
  density ≥ 4 pulses/m², otherwise 1.0 m. All four scouted AOIs are 10–20
  pulses/m², so 0.5 m applies.
- Gaussian smooth, σ = 0.5 m (declared), as normalized convolution so NA cells
  do not pull heights down. This departs from the repository's 3×3 mean
  pre-LM smooth because the spec asks for a Gaussian.

### Variable-window local maxima

- Window as a function of height, density-aware floor (declared):
  `ws(h) = clamp(w0 + 0.15 (h - 1), w0, 5)`, with
  `w0 = max(1.5, 2.5 × pulse spacing)` metres.
- `hmin = 1.0 m` for extraction, below the 1.5 m band edge, so the histogram
  shows the drop-off.
- Implement the VWF on the smoothed raster in terra: bin `ws` to 0.25 m
  steps, one `focal(max)` per bin with a disc kernel, a cell is a top when it
  equals its own-bin focal max and ≥ hmin; collapse plateaus with
  `patches()` and keep one cell per patch. Reason: lasR's
  `local_maximum_raster()` runs inside a point-cloud pipeline and cannot take
  the terra-smoothed, reprojected raster.
- Cross-check against lasR: run `local_maximum_raster(pf, ws_3857)` with
  `ws_3857(h) = k × ws(h)` on the unsmoothed 3857 CHM and the terra VWF on the
  same raster; report counts and 1:1 matches within one cell. This validates
  the terra implementation against lasR's native VWF.
- Per top: `h` from the unsmoothed CHM, `h_smooth`, and a crown radius from
  the smoothed CHM: walk 8 rays until the value drops below 0.55 × h
  (dalponte `th_cr`), rises more than 0.5 m (saddle into a neighbour), hits NA
  or 10 m; radius = median ray length.

### Floor estimates (the point of step 1)

Two estimates per AOI, both written to `label_floor.json`:

1. Density rule: the smallest reliably detectable crown is about 2.5 × pulse
   spacing (repository methodology). Using this AOI's own profile crown radii,
   the floor is the lowest 0.5 m height bin whose median crown diameter
   reaches that size.
2. Histogram knee: mode of the 0.25 m histogram of top heights (3-bin running
   mean). Below the mode, counts fall even though true abundance of small
   trees normally rises, so detection is failing there.

Declared label floor = max(1.5, estimate 1, estimate 2). If it lands above
1.5 m, the 1.5 m–floor bin is reported but not supervised. Caveat: the
histogram cannot separate shrubs from saplings.

Also record acquisition dates from `summarise(metrics = c("gpstime_min",
"gpstime_max"))`: adjusted standard GPS time + 1e9 s from 1980-01-06.

## Steps 2–5: Python package

### Pairing with NAIP (`naip.py`)

- Search Planetary Computer STAC collection `naip` (pystac-client +
  planetary-computer), or take local GeoTIFFs. Keep items within 365 days of
  the LiDAR median date; prefer NAIP acquired after the LiDAR.
- Resample the 4 bands (R, G, B, NIR) onto the AOI frame at 0.3 m.
- Disturbance check (the spec's "drop pairs where NDVI change indicates
  harvest or fire"): with one NAIP date, measure disagreement with the LiDAR
  canopy: fraction of CHM ≥ 5 m pixels with NAIP NDVI < 0.1. Mask 30 m blocks
  above 10 %; drop the pair if more than 25 % of blocks are masked. Limitation:
  if NAIP precedes the LiDAR, a disturbance in between is not visible to this
  check.
- Co-registration: FFT cross-correlation of NDVI with the CHM canopy mask
  within ±3 m, sub-pixel peak; shift labels if the peak is clear, record it,
  flag the pair otherwise. Relief displacement is not fixed by this: NAIP is
  orthorectified to the ground, so an apex shifts by h·tan(view angle), up to
  ~1.5 m for a 5 m tree at 17° off nadir. Record it as a limitation.

### Sun geometry (`sun.py`)

- NOAA solar position from date, time, lat, lon.
- NAIP STAC items carry a date but no time. Estimate the solar azimuth from
  the image: cross-correlate the CHM with image darkness (shadows fall on the
  anti-sun side), then take the time of day at which the NOAA azimuth matches,
  and read the elevation at that time.
- Channels: constant planes sin(az), cos(az), sin(elev). Augmentation rotates
  and mirrors the azimuth with the image.

### Targets (`targets.py`)

- σ by height, in metres so it is grid-independent:
  `σ_px_native(h) = clip(1 + 5 (h - 1.5) / 28.5, 1, 6)` at 0.3 m, i.e. a
  1.5 m sapling σ ≈ 1 px, a 30 m conifer σ ≈ 6 px, as in the spec. Option:
  σ = 0.5 × crown radius.
- Render CenterNet-style: max of Gaussians, nearest pixel to each top set to
  exactly 1.
- Weights on the negative term: 1 by default; 0 (ignore) in discs around tops
  below the floor, masked blocks, nodata, the AOI edge buffer and other split
  blocks; 0.25 (declared) for "uncertain vegetation": NDVI above threshold and
  outside every labelled top's occupancy disc of radius max(3 px, crown
  radius). The occupancy exclusion keeps crown flanks of large trees fully
  negative.

### Loss (`losses.py`)

Penalty-reduced focal loss (CenterNet), α = 2, β = 4, computed from logits
with `logsigmoid`, negatives multiplied by the weight map, normalized by the
number of positives. Head bias initialised to −2.19.

### Models (`models.py`)

- Step 2, `UNetSmall`: 4 levels, base 32 channels, input R,G,B,NIR at 0.3 m,
  stride-1 output.
- Step 3, `DinoHeatmapNet`: tiles upsampled 2× (0.15 m). Frozen DINOv3
  ViT-B/16 on RGB (ImageNet normalisation) gives 768-d tokens at stride 16.
  A cheap CNN stem on all bands gives features at strides 1, 2, 4, 8. The head
  projects tokens to 256 channels and upsamples ×2 four times, concatenating
  the stem feature at each stride, to a stride-1 heatmap (16× in total).
  Load the backbone with
  `torch.hub.load(<dinov3 repo>, "dinov3_vitb16", source="local",
  weights=<checkpoint>)` and `get_intermediate_layers(x, n=1, reshape=True,
  norm=True)`, or from Hugging Face `transformers`, dropping the CLS and
  register tokens. The weights are gated and must be downloaded separately.
- Step 4: add the sun planes and a CHMv2 raster as extra stem channels. CHMv2
  is taken as a precomputed GeoTIFF from the CHMv2 inference code in the
  DINOv3 repository. Caveat: if CHMv2 was trained on LiDAR over these areas,
  it carries label information; check its training regions before
  interpreting a gain.

### Data and splits (`dataset.py`)

- Per AOI stack: NAIP uint8 bands on the 0.3 m frame plus a mask raster;
  targets rendered on the fly from `tops.csv` so σ and floor changes need no
  re-preparation.
- Splits: `aoi` mode (held-out AOIs, the real experiment) or `blocks` mode
  (120 m blocks hashed 70/15/15 for pilots). Training crops lie inside one
  train block; validation and test are tiled per block, so no image context
  leaks.
- Chips: 256 native px for the U-Net, 128 native px → 256 upsampled for
  DINOv3.

### Training (`train.py`)

AdamW, cosine schedule, AMP on CUDA, flips and 90° rotations (sun channels
transformed with the image), ±10 % per-band gain. Early stopping on validation
F1 in the 1.5–5 m band at the best threshold. Writes `best.pt`, the resolved
config and validation metrics.

### Inference (`predict.py`, `peaks.py`)

Sliding windows with 25 % overlap, keep each window's interior. Peaks: sigmoid
→ max-pool NMS with a 0.9 m kernel → threshold → map coordinates. The
operating threshold is chosen on validation and frozen for test.

### Evaluation (`evaluate.py`, `score.py`)

- Hungarian matching, solved per connected component of the candidate graph
  (KD-tree pairs), tolerance `max(1 m, 0.3 × crown radius)` per reference.
- Height bins: <1.5, 1.5–3, 3–5, 5–10, 10–20, ≥20 m, plus the 1.5–5 m band.
  References binned by their height; matched predictions take the reference's
  bin; unmatched predictions take the CHM height at their location.
- Pool by summing TP/FP/FN, never by averaging rates.
- Paired block bootstrap (120 m blocks, 2000 replicates) for every F1 and
  every model-versus-model difference.
- Independent check: NEON SOAP stems (`ground_truth_stems.csv` from
  `neon_ground_truth.R`, plot cores from `plot_centroids.csv`), crown radius
  from `maxCrownDiameter / 2`. Caveat: NEON maps stems mainly ≥ 10 cm DBH,
  so the 1.5–5 m bins there will be thin; report n per bin.

### Semi-supervised round (`semi.py`, step 5)

Only if recall in 1.5–3 m is the bottleneck. From train-split predictions,
take peaks with score ≥ 0.5, NDVI above threshold, outside every label's
occupancy disc; add them with weight 0.5 and retrain from the best checkpoint.
Evaluation against 3DEP labels will count recovered small trees as false
positives, so the NEON check is the arbiter for this step.

## Experiment sequence (from the spec)

1. Labels + height histogram on the CA/OR AOIs; freeze the floor.
2. U-Net baseline, RGB+NIR, stride-1, height-scaled σ, focal loss.
3. Frozen DINOv3 ViT-B/16 on 2×-upsampled tiles with the upsampling head;
   compare height-binned F1 with paired intervals.
4. Add sun geometry and CHMv2.
5. Semi-supervised round if 1.5–3 m recall is still the bottleneck.

## Testing plan

- R: synthetic CHM with known cones checks the VWF (count, positions,
  plateau collapse), the Gaussian normalized convolution, the profile crown
  radius and the floor estimators.
- Python: synthetic scenes (crowns with lit/shadow sides cast from a known
  sun) check target rendering, focal loss values, peak extraction,
  Hungarian matching and binning, co-registration recovery of a known shift,
  shadow-based azimuth recovery, and a tiny CPU train → predict → score loop.
