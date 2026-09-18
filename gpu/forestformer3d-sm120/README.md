# ForestFormer3D on Blackwell (sm_120)

ForestFormer3D (ICCV 2025, `SmartForest-no/ForestFormer3D`) ported to run on
the **RTX 5090** (sm_120) under **torch 2.7.0 / CUDA 12.8** — upstream is torch
1.13 / cu116 and does not run on Blackwell. Verified end-to-end: the model
loads the official `epoch_3000_fix.pth`, runs inference on a point-cloud plot, and
emits per-tree instance masks.

## Historical sparse NEON smoke test

A NEON SJER plot (31,676 pts, ~3.5 pts/m²) through the pretrained model:

```text
raw instance candidates: 101   instance score range: 0.023 .. 0.273
model per-point assignment: 8 trees (18.4% of points)
score>=0.10: 35 candidate trees   score>=0.15: 14
```

These are historical fallback-path outputs, not evidence that the native
inference path was correct or that domain shift alone explained the result.
The pinned model dispatches on `test` in the input path. The benchmark driver
now stages `test_cyl_*` scenes, reads the complete saved PLY rather than the
last-region return value, and validates point order, label ranges, coordinate
restoration, and per-point confidence. See the
[frozen transfer audit](../../results/frozen-transfer-audit-results.md).

## The four hard problems (and fixes)

1. **MinkowskiEngine voxelizer** (sm_120 wall). FF3D's `collate()` is pure ME and
   `oneformer3d.py` imports ME at module top. Solved by the shared
   [`../minkowski-sm120`](../minkowski-sm120) build (ME 0.5.4 for arch 12.0).
2. **spconv backbone** (SpConvUNet). `spconv-cu128` 2.4.1 + `cumm-cu128` 0.9.1
   from the rathaROG index run on sm_120. `cumm-cu128` must come
   from rathaROG, not PyPI; and keep `ccimport>=0.4.4` / `pccm>=0.4.16` (older
   pins break `cumm`'s `IsAppleSiliconMacOs`).
3. **mmcv `_ext` build on torch 2.7.** No cu128 wheel exists, so it compiles from
   source — and mmcv 2.0.0 hardcodes `-std=c++14` while torch 2.7 headers need
   **C++17** (`jit_type.h operator*`, `c10` hash errors). `sed c++14 -> c++17` in
   `setup.py` fixes it. See `build_mmcv.sh`.
4. **spconv checkpoint layout.** `epoch_3000_fix.pth` is already in spconv-cu128
   2.4.1 layout `(out,K,K,K,in)`; FF3D's in-memory `permute(1,2,3,4,0)` in
   `tools/test.py` **re-breaks** it. Disable the permute (load as-is).

## Dependency-port notes

- **numpy < 2 track** (`numpy==1.26.4`, `numba==0.59.1`): the old mm-stack needs
  it; `spconv-cu128` + ME both import fine under it.
- **mm-stack** pinned to FF3D's: `mmengine 0.7.3`, `mmdet 3.0.0`, `mmsegmentation
  1.0.0`, `mmdet3d @ 22aaa47` — all `--no-deps`. Exact env in `ff3d_freeze.txt`.
- **opencv-python-headless** (slim base lacks libGL); **open3d** needs apt
  `libgl1 libgomp1 libx11-6 libxext6 libxrender1 libsm6 libglib2.0-0 libusb-1.0-0`
  plus `plotly`/`dash`; `mmdet3d.evaluation` eagerly imports `lyft_dataset_sdk`
  `nuscenes-devkit`. The Karbo123 **segmentator is NOT needed** — it is mesh-only
  and the point-cloud test pipeline computes voxel-superpoints in the model.
- **torch-scatter 2.1.2 / torch-cluster 1.6.3 / torch-points-kernels 0.7.0** built
  for arch 12.0.

## Data prep (no batch_load)

`batch_load_ForAINetV2_data.py` pulls in segmentator/open3d/Delaunay and forces
labelled mode. `prep_test_data.py` bypasses it: writes the
`forainetv2_instance_data/*_vert/_sem/_ins/_bbox.npy` that `converter_forainetv2`
consumes (dummy sem=0/ins=0, empty `(0,7)` bboxes → `gt_num=0`). Then
`tools/create_data_forainetv2.py` builds `points/*.bin` + the test pkl. (Update
only the **test** pkl — `update_pkl_infos` crashes on the empty train/val pkls.)

## Run

The supported benchmark entry point is `ff3d_entry.sh`, which invokes
`ff3d_arm.py <input_laz_or_directory> <output.laz> <checkpoint>` inside an
isolated copy of the model checkout. A single LAZ stages one native `test_*`
scene; the model retains its own internal overlapping-region inference. The
export preserves original integer coordinates, scales, offsets and input rows,
with `ff3d_row` as the zero-based source index, `PointSourceID` as the instance
label (zero background), and aligned `ff3d_score`. No outer deduplication or
nearest-neighbor reference projection is applied to indexed scene outputs.

The external driver exposes this path through `FF_LAYOUT=whole_scene`; its
default `FF_LAYOUT=cylinders` remains available for historical reproduction.
Use a new output directory because layout and adapter sources are part of the
cache provenance. See the [scene protocol](../../docs/forestformer-scene-assembly-protocol.md)
and [training comparison](../../results/forestformer-scene-assembly-results.md)
for the bounded resource result, native conflict policy and eligibility limits.
CPU export regressions run with `gpu/.venv/bin/python tests/test_transfer_exports.py`.

The commands below are historical port smoke tests;
`run_infer_save.py` is not the corrected full-scene benchmark adapter.

```sh
# build the image (FROM the proven ME base) — see Dockerfile
docker build -t ff3d-sm120 .
# inside a container with the FF3D repo + weights mounted:
python prep_test_data.py                       # stage a plot (SRC=*.laz)
python tools/create_data_forainetv2.py forainetv2 --root-path ./data/ForAINetV2
python run_infer_save.py                        # -> work_dirs/infer/pred_instances.laz
```

`ff3d_repo.patch` carries the four `tools/test.py` + config edits. `ff3d_freeze.txt`
is the authoritative version lock (177 packages) for the working container.
