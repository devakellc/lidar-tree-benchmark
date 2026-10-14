# ForestMamba on Blackwell (sm_120)

ForestMamba ([arXiv 2606.01549](https://arxiv.org/abs/2606.01549), BMVC 2026)
is a fork of the ForestFormer3D code with a sparse Mamba encoder, a Mamba query
decoder and tree queries seeded at canopy-height-model peaks. This directory
runs the authors' released checkpoint zero-shot on the NEON frozen clips with
the **RTX 5090** (sm_120), torch 2.7.0 and CUDA 12.8. Upstream targets torch
1.13 / CUDA 11.6 and does not run on Blackwell.

## Provenance

| Item | Value |
|---|---|
| Upstream code | `thanhhff/ForestMamba` at the commit in [ForestMamba.commit](../ForestMamba.commit) |
| Checkpoint | `v6_epoch_1500_fix.pth`, 244,449,409 bytes, SHA-256 pinned in [CHECKSUMS.sha256](../CHECKSUMS.sha256) |
| Checkpoint source | The authors' public Google Drive folder `1wf_IcXNIZgxOg_Dkrt45ph2ssdBeWCHm`, linked from the upstream README |
| Configuration | `configs/ForAINetv2/forestmamba_chm_radius16_qp300_2many_v6.py` |
| Training data | FOR-instanceV2: drone, terrestrial and mobile laser scanning; no airborne scans |
| License | Code: CC BY-NC 4.0, as ForestFormer3D and OneFormer3D, so non-commercial use only. The checkpoint, linked from the upstream README, states no separate licence |

The release checkpoint was trained with synchronized batch normalisation; the
upstream README states that it scores above the paper's numbers. The model's
allometric window parameters for the canopy-height peaks are stored at their
initial values (0.25 and 0.5), so the peak window is fixed, not learned.

## Environment

[`Dockerfile`](Dockerfile) builds `forestmamba-sm120` **from the ForestFormer3D
image** (`ff3d-sm120`, see [../forestformer3d-sm120](../forestformer3d-sm120)):
the same torch, spconv, MinkowskiEngine and OpenMMLab stack, plus the Mamba
kernels and the upstream mmengine/mmdet3d file swaps. The swaps (`base_model.py`
with the `epoch` argument the driver calls, and `transforms_3d.py`) are copied
from the pinned checkout at build time, so the image does not depend on how its
base was built; they are byte-identical to ForestFormer3D's. The benchmark's
base image was `sha256:fd60f5cdc5ae…`, the image of the ForestFormer3D paper
runs; `setup.sh` warns when the local base differs.
[`fm_freeze.txt`](fm_freeze.txt) is the version lock of the result. Against the
committed ForestFormer3D lock it adds the nine packages the Dockerfile installs
and four that the base image carries beyond that lock (`markdown-it-py`,
`mdurl`, `importlib-metadata` 9.0.0 and `ninja` 1.11.1.4); none is on the
numerical path.

- **Mamba kernels.** Prebuilt `mamba-ssm 2.3.2.post1` and `causal-conv1d
  1.6.2.post1` wheels for torch 2.7, CUDA 12 and Python 3.11, pinned by URL and
  SHA-256. Built with CUDA 12.9, they carry sm_120 kernels, so nothing is
  compiled. Upstream pins 1.1.1; the Mamba v1 block it uses keeps its
  parameter names in 2.3.2, and its kernels matched the PyTorch references
  forward and backward on the 5090.
- **transformers 4.46.3.** `import mamba_ssm` loads the language-model head,
  which needs a generation API that upstream's `transformers==4.36.0` lacks.
- mamba-ssm 2.3 also lists tilelang, quack-kernels and triton 3.5 for its
  Mamba-2/3 kernels. The Mamba v1 block never calls them; pip reports them as
  unmet requirements at build time.

Set up the checkout, the verified checkpoint and the image with:

```sh
bash gpu/forestmamba-sm120/setup.sh      # needs the ff3d-sm120 image
```

## Driver contract

[`fm_arm.py`](fm_arm.py) takes one raw-with-ground LAZ and writes one LAZ
(`fm_entry.sh` is the container entry; the arm runs it as the invoking user):

- The clip is staged as one native `test_*` scene and the upstream
  sliding-cylinder test route runs once over it. Classified noise (ASPRS
  classes 7 and 18) stays out of the scene and is exported as background.
  ForestMamba reads staged z as height: its canopy-peak queries keep peaks of at
  least 1.5 m and search a window of 0.25·h^0.5 m, and its decoder orders
  queries vertically. z is therefore measured from the lowest ground return
  (the lowest remaining return when a clip has no ground), not from the lowest
  return of any class: one noise return 30 m below ground would otherwise raise
  every height by 30 m, and decimation keeps or drops it rung by rung. x and y
  are centred on their mean, because float32 cannot hold UTM coordinates to the
  centimetre.
- The sweep refuses a checkpoint whose SHA-256 is not the one pinned in
  [CHECKSUMS.sha256](../CHECKSUMS.sha256). [`fm_checkpoint.py`](fm_checkpoint.py)
  then reads only a plain torch zip archive (legacy, tar and TorchScript files
  are refused before anything is unpickled) through an unpickler that resolves
  only the audited globals (torch tensor rebuilds, numpy arrays, `OrderedDict`)
  and never instantiates the logger objects stored next to the weights. The
  state is loaded with a **strict** `load_state_dict`: mmengine's own loader
  only warns on missing or mis-shaped tensors. The release stores its 49
  sparse-convolution weights as `(k,k,k,in,out)`; mmdet3d's spconv-2 load hook
  permutes them to spconv 2's `(out,k,k,k,in)`, verified tensor by tensor.
- ForestMamba saves -1 background and dense instance IDs 1..M (ForestFormer3D
  saves zero-based IDs). [`fm_export.py`](fm_export.py) maps -1 to 0, keeps
  1..M, and rejects any other label, a gap in the numbering, a changed point
  count, order or coordinate, and invalid confidence.
- The output is the ForestFormer3D whole-scene schema: every input row in order
  with its original coordinates and scales, the instance in `PointSourceID`,
  `UserData` 0, the per-point confidence in `ff3d_score` and the source row in
  `ff3d_row`. `ff3d_scene_check` and `ff3d_collapse` read it unchanged.
- The receipt (`<out>.laz.json`) records the seed, the determinism settings,
  the strict load, the configuration, the height-origin rule and the number of
  noise rows left out, timings, peak memory, the staging offset, the instance
  and background counts, the semantic label counts and the package versions.

**Repeatability.** Python, numpy and torch are seeded before the scene,
because the query supplement's farthest-point sampling draws a random start,
and torch's deterministic algorithms are on. Two runs of the same clip still
differ slightly, because the sparse-convolution and voxel-hashing CUDA kernels
are outside torch's control. On the SOAP_031 native clip, 95% of one run's
instances had a match at IoU 0.5 or higher in the other, and 94.7% of points
agreed on tree versus background. Deterministic mode costs about 8% of
inference time. The benchmark report measures the variation on repeated runs.

## Port check

[`fm_parity.py`](fm_parity.py) compares this port with the authors' own
published predictions of the same checkpoint on three FOR-instanceV2 test
scenes. Each scene's published points, already in local coordinates and
without ASPRS classes, go through the driver's staging, strict load and test
route, and both prediction sets are scored by the authors' evaluator
(`tools/eval_predictions.py`) against the same reference labels. Run on the
authors' predictions, the evaluator reproduces their published per-scene table
exactly.

| Scene | Points | Authors P / R / F1 | This port P / R / F1 | F1, earlier run | Authors' instances matched (IoU ≥ 0.5) | Tree/background agreement |
|---|---:|---|---|---:|---:|---:|
| RMIT | 260,438 | 0.839 / 0.812 / 0.825 | 0.839 / 0.812 / 0.825 | 0.839 | 61 of 62 | 99.4% |
| NIBIO2 plot 15 | 489,366 | 0.989 / 0.912 / 0.949 | 0.989 / 0.922 / 0.954 | 0.954 | 94 of 94 | 99.1% |
| TUWIEN | 1,401,559 | 0.839 / 0.743 / 0.788 | 0.871 / 0.771 / 0.818 | 0.788 | 31 of 31 | 99.0% |

The table is the final image's run; the earlier run, with the same model path,
shows the run-to-run variation (up to 0.03 F1 on a scene). The port reproduces
the release within that variation. These are the checkpoint's own test scenes,
not airborne data; they show that the Blackwell port preserves the model, not
how it transfers to NEON.

The authors' predictions are files of their public Google Drive folder (the
checkpoint's folder):

| File | Drive file ID | SHA-256 |
|---|---|---|
| `RMIT_RMIT_test_test.ply` | `15Mf8zsVxrOsaD_P_ggu14KT9S1iwgQ7j` | `bec57ec7275299fed42317e4e9bc49f68c9f94d232fecf44e61e663e07909380` |
| `NIBIO2_NIBIO2_plot15_annotated_test.ply` | `17Ed1IxDwQHyENonXXZuox_Yo3WdtanrI` | `51d3906f412d180ee96d548ac2e6a9490b91d13a1f758608599c51d36a2849e1` |
| `TUWIEN_TUWIEN_test_test.ply` | `10EpaognmjfeQwFKkHCOwCO3XId2_MHy2` | `82b1fa231d939098cff76cf6fb71fc179c0b6383117bf67b1e87dde31fa07857` |

With the three files in `IN` and a new output directory `OUT`, the check runs
in the image on a copy of the pinned checkout, as the arm does:

```sh
GPU=$PWD/gpu; STORE=$GPU/store/forestmamba; WS=$(mktemp -d); mkdir -p "$OUT"
rsync -a --exclude=.git --exclude=data --exclude=work_dirs "$STORE/ForestMamba/" "$WS/"
docker run --rm --gpus all --network none --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -e PYTHONHASHSEED=0 -e WANDB_MODE=disabled \
  -v "${WS}:${WS}" -v "${STORE}:${STORE}:ro" -v "${IN}:${IN}:ro" -v "${OUT}:${OUT}" \
  -v "${GPU}/forestmamba-sm120:${GPU}/forestmamba-sm120:ro" \
  -v "${GPU}/forestformer3d-sm120:${GPU}/forestformer3d-sm120:ro" \
  -w "$WS" forestmamba-sm120 \
  python "$GPU/forestmamba-sm120/fm_parity.py" "$STORE/v6_epoch_1500_fix.pth" "$OUT" 0 \
  "$IN/RMIT_RMIT_test_test.ply" "$IN/NIBIO2_NIBIO2_plot15_annotated_test.ply" \
  "$IN/TUWIEN_TUWIEN_test_test.ply"
```

It writes `OUT/parity.json`, the source of the table, and each scene's points
with this port's predictions and the authors' reference labels.

## Run

The NEON density-ladder arm is
[`scripts/detect_forestmamba_sweep.R`](../../scripts/detect_forestmamba_sweep.R).
The gated live test pushes a synthetic UTM scene through the container:

```sh
FM_REPO=$PWD/gpu/store/forestmamba/ForestMamba \
FM_CKPT=$PWD/gpu/store/forestmamba/v6_epoch_1500_fix.pth \
  Rscript tests/run_tests.R
```

On the 5090 a native tower clip takes a median 55 s per cell, container start
to export, of which 44 s are inference over its overlapping 16 m cylinders; a
native distributed clip takes 38 s. Torch allocates at most 679 MiB of GPU
memory on the ladder (2.4 GiB reserved). The
[benchmark report](../../results/forestmamba-results.md#compute) gives the
compute per rung.
