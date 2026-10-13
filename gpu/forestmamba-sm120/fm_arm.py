#!/usr/bin/env python
"""ForestMamba benchmark arm: one whole scene in, one row-indexed LAZ out.

Stages one LAZ as a native ForAINetV2 `test_*` scene, centred on its mean x/y
and minimum z because float32 cannot hold UTM coordinates to the centimetre.
Runs the upstream sliding-cylinder test route of the pinned ForestMamba
checkout once, then writes every input row back in order: PointSourceID is the
instance (0 = background), UserData 0, ff3d_score the aligned per-point
confidence and ff3d_row the source row. This is the ForestFormer3D whole-scene
schema, so its readers (ff3d_scene_check, ff3d_collapse, the crown and IoU/PQ
arms) apply unchanged.

The checkpoint goes through fm_checkpoint's restricted unpickler and a strict
load_state_dict: a missing, unexpected or mis-shaped tensor is an error, where
mmengine's own loader only warns. torch, numpy and Python are seeded before
the scene (the farthest-point query supplement draws a random start) and
torch's deterministic algorithms are on. Runs still differ slightly: the
sparse-convolution and voxel-hashing CUDA kernels are outside torch's control.

Run from the ForestMamba checkout root:
    python fm_arm.py <input.laz> <out.laz> <checkpoint> [<seed>]
Writes <out.laz> and its receipt <out.laz>.json.
"""
import json
import os
import random
import resource
import shutil
import sys
import time

import numpy as np

# Before torch initialises CUDA: deterministic cuBLAS workspaces.
os.environ.setdefault("CUBLAS_WORKSPACE_CONFIG", ":4096:8")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from fm_export import (EMPTY_SAMPLE_ERROR, native_scene_name,  # noqa: E402
                       restore_dense, scene_output, validate_empty_sample_error)

CONFIG = "configs/ForAINetv2/forestmamba_chm_radius16_qp300_2many_v6.py"
ROOT = "data/ForAINetV2"                       # relative to the checkout (ephemeral)
INST = os.path.join(ROOT, "forainetv2_instance_data")
META = os.path.join(ROOT, "meta_data")
WORK_DIR = "./work_dirs/arm"
# Row batch of the exact nearest-neighbour mapping (same result as upstream's
# 20,000 rows, bounded memory on native-density ALS).
NN_CHUNK = 2048


def seed_everything(seed):
    import torch
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False
    # warn_only: index_reduce's CUDA amax has no deterministic variant (its
    # values do not depend on order).
    torch.use_deterministic_algorithms(True, warn_only=True)


def stage_scenes(scenes):
    """Write (scan, points[, semantic, instance]) scenes as ForAINetV2 test data.

    Builds the info files in-process and updates only the test pickle: the
    stock tools/create_data_forainetv2.py also updates the empty train/val
    pickles and fails on them.
    """
    for d in (INST, META):
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d, exist_ok=True)
    for scene in scenes:
        scan, points = scene[0], np.asarray(scene[1], dtype=np.float32)
        n = len(points)
        labels = list(scene[2:4]) + [None] * (2 - len(scene[2:4]))
        np.save(f"{INST}/{scan}_vert.npy", points)
        for name, value in zip(("sem", "ins"), labels):
            np.save(f"{INST}/{scan}_{name}_label.npy",
                    np.zeros(n, np.int64) if value is None else np.asarray(value, np.int64))
        np.save(f"{INST}/{scan}_unaligned_bbox.npy", np.zeros((0, 7), np.float32))
        np.save(f"{INST}/{scan}_aligned_bbox.npy", np.zeros((0, 7), np.float32))
        np.save(f"{INST}/{scan}_axis_align_matrix.npy", np.eye(4))
    with open(f"{META}/test_list.txt", "w") as stream:
        stream.write("".join(scene[0] + "\n" for scene in scenes))
    for split in ("train", "val"):
        open(f"{META}/{split}_list.txt", "w").close()
    from converter_forainetv2 import create_info_file
    from update_infos_to_v2 import update_pkl_infos
    create_info_file(ROOT, "forainetv2", ROOT, workers=1)
    update_pkl_infos("forainetv2", out_dir=ROOT,
                     pkl_path=os.path.join(ROOT, "forainetv2_oneformer3d_infos_test.pkl"))


def build_model(checkpoint):
    """The published v6 model with the checkpoint loaded strictly."""
    from mmengine.config import Config
    from mmengine.runner import Runner
    import oneformer3d  # noqa: F401  registers the ForestMamba modules
    from fm_checkpoint import load_state_dict
    cfg = Config.fromfile(CONFIG)
    cfg.work_dir = WORK_DIR
    cfg.test_dataloader.dataset.data_root = ROOT + "/"    # upstream: an absolute path
    cfg.vis_backends = [dict(type="LocalVisBackend")]
    cfg.visualizer.vis_backends = cfg.vis_backends
    cfg.model.chunk = NN_CHUNK
    cfg.load_from = None
    cfg.resume = False
    runner = Runner.from_cfg(cfg)
    model = runner.model
    # mmdet3d's spconv-2 hook converts the released (k,k,k,in,out) sparse-conv
    # weights to spconv 2's (out,k,k,k,in) during this load.
    model.load_state_dict(load_state_dict(checkpoint), strict=True)
    model.eval()
    os.makedirs(WORK_DIR, exist_ok=True)
    model._output_path = WORK_DIR             # upstream derives it from sys.argv
    return runner, model


def infer_scenes(runner, model, scans, seed):
    """Yield (scan, staged points, saved PLY vertices, empty-return error, receipt)."""
    import torch
    from plyfile import PlyData
    for i, data in enumerate(runner.test_dataloader):     # ordered as staged
        scan = scans[i]
        lidar_path = data["data_samples"][0].lidar_path
        if os.path.splitext(os.path.basename(lidar_path))[0] != scan or "test" not in lidar_path:
            raise ValueError("Unexpected input order or upstream inference route")
        saved = os.path.join(WORK_DIR, scan + ".ply")
        if os.path.exists(saved):
            os.remove(saved)
        seed_everything(seed)
        torch.cuda.reset_peak_memory_stats()
        start, empty = time.time(), None
        try:
            with torch.no_grad():
                model.test_step(data, epoch=0)
        except AssertionError as error:
            # Upstream saves a valid all-background scene before a typed setter
            # rejects its None last-region return; any other failure is fatal.
            if str(error) != EMPTY_SAMPLE_ERROR or not os.path.exists(saved):
                raise
            empty = error
        seconds = time.time() - start
        points = data["inputs"]["points"]
        points = (points[0] if isinstance(points, list) else points).detach().cpu().numpy()[:, :3]
        staged = np.load(f"{INST}/{scan}_vert.npy")
        if not np.array_equal(staged, points):
            raise ValueError("Test pipeline changed staged point order or coordinates")
        receipt = dict(scene=scan, lidar_path=lidar_path, points=len(points),
                       infer_seconds=round(seconds, 3), empty_sample_return=empty is not None,
                       peak_cuda_allocated_bytes=torch.cuda.max_memory_allocated(),
                       peak_cuda_reserved_bytes=torch.cuda.max_memory_reserved())
        yield scan, points, PlyData.read(saved)["vertex"].data, empty, receipt


def versions():
    import importlib.metadata as md
    found = {}
    for name in ("torch", "mamba_ssm", "causal_conv1d", "spconv-cu128", "mmdet3d", "mmengine"):
        try:
            found[name] = md.version(name)
        except md.PackageNotFoundError:
            found[name] = None
    return found


def main(argv):
    in_laz, out_laz, checkpoint = argv[1:4]
    seed = int(argv[4]) if len(argv) > 4 else 0
    start = time.time()
    # The driver is mounted outside the checkout: put the checkout (cwd) and its
    # tools/ on the path for the oneformer3d package and the data converters.
    sys.path.insert(0, os.getcwd())
    sys.path.insert(0, os.path.join(os.getcwd(), "tools"))
    import laspy
    source = laspy.read(in_laz)
    scan = native_scene_name(in_laz)
    xyz = np.column_stack([source.x, source.y, source.z]).astype(np.float64)
    receipt = dict(scene=scan, layout="whole_scene", route="upstream_test", seed=seed,
                   deterministic_algorithms=True,
                   pythonhashseed=os.environ.get("PYTHONHASHSEED"),
                   checkpoint_load="strict", config=CONFIG, nn_chunk=NN_CHUNK,
                   source_rows=len(source.points))
    if not len(xyz):
        scene_output(source, np.zeros(0, dtype=int), np.zeros(0)).write(out_laz)
        receipt.update(points=0, instances=0, background=0, route="empty_input")
    else:
        offset = np.array([xyz[:, 0].mean(), xyz[:, 1].mean(), xyz[:, 2].min()])
        staged = (xyz - offset).astype(np.float32)
        from mmdet3d.utils import register_all_modules
        register_all_modules()
        stage_scenes([(scan, staged)])
        loaded = time.time()
        runner, model = build_model(checkpoint)
        model_seconds = time.time() - loaded
        (_, points, vertices, empty, run), = list(infer_scenes(runner, model, [scan], seed))
        _, ids, scores = restore_dense(points, vertices, offset)
        if empty is not None:
            validate_empty_sample_error(empty, ids)
        # The export keeps the exact source rows, not the rounded PLY positions.
        if not np.array_equal(staged, (np.column_stack(
                [source.x, source.y, source.z]) - offset).astype(np.float32)):
            raise ValueError("Whole-scene source changed during inference")
        scene_output(source, ids, scores).write(out_laz)
        semantic = np.asarray(vertices["semantic_pred"])
        receipt.update(run, model_seconds=round(model_seconds, 3), offset=offset.tolist(),
                       instances=int(len(np.unique(ids[ids > 0]))),
                       background=int((ids == 0).sum()),
                       semantic_counts={int(k): int(c) for k, c in
                                        zip(*np.unique(semantic, return_counts=True))},
                       versions=versions())
    receipt.update(total_seconds=round(time.time() - start, 3),
                   peak_host_rss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
    with open(out_laz + ".json", "w") as stream:
        json.dump(receipt, stream, indent=2)
    print(f"{scan}: {receipt['points']} pts, {receipt['instances']} instances")
    print("ARM_DONE")


if __name__ == "__main__":
    main(sys.argv)
