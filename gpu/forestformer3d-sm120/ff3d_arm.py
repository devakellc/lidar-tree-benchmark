#!/usr/bin/env python
"""FF3D benchmark arm: stage every cylinder clip in <in_dir> as a ForAINetV2
scene, run FF3D once over all of them, and write ONE merged UTM LAZ <out_laz>
(point_source_id = per-cylinder instance id, user_data = cylinder/block index,
instance score in an extra dim). Run from the FF3D repo root.

Usage: python ff3d_arm.py <in_dir> <out_laz> <ckpt>
"""
import os, sys, glob, shutil, json
import numpy as np
import laspy
from plyfile import PlyData
from ff3d_export import (native_scene_name, restore_native, validate_las_ids,
                         EMPTY_SAMPLE_ERROR, validate_empty_sample_error)

_orig = __import__("torch").load
def _load(*a, **k):
    k.setdefault("weights_only", False); return _orig(*a, **k)
__import__("torch").load = _load

IN_DIR, OUT_LAZ, CKPT = sys.argv[1], sys.argv[2], sys.argv[3]
# This driver is mounted from outside the repo, so sys.path[0] is its own dir,
# not the repo root. Add the repo root (cwd, set by ff3d_entry.sh `cd $repo`) so
# the repo-local `oneformer3d` package + tools/ helpers import.
sys.path.insert(0, os.getcwd()); sys.path.insert(0, os.path.join(os.getcwd(), "tools"))
ROOT = "data/ForAINetV2"                       # relative to repo CWD (ephemeral)
INST = os.path.join(ROOT, "forainetv2_instance_data")
META = os.path.join(ROOT, "meta_data")
for d in (INST, META):
    shutil.rmtree(d, ignore_errors=True); os.makedirs(d, exist_ok=True)

# 1. stage each cylinder as a scene; remember its centering offset for UTM restore
clips = sorted(glob.glob(os.path.join(IN_DIR, "cyl_*.laz")))
offsets, scans = {}, []
for clip in clips:
    scan = native_scene_name(clip)
    las = laspy.read(clip)
    xyz = np.vstack([las.x, las.y, las.z]).T.astype(np.float64)
    if xyz.shape[0] < 50:                                     # too sparse -> skip
        continue
    off = np.array([xyz[:, 0].mean(), xyz[:, 1].mean(), xyz[:, 2].min()])
    offsets[scan] = off
    pts = (xyz - off).astype(np.float32)
    n = pts.shape[0]
    np.save(f"{INST}/{scan}_vert.npy", pts)
    np.save(f"{INST}/{scan}_sem_label.npy", np.zeros(n, np.int64))
    np.save(f"{INST}/{scan}_ins_label.npy", np.zeros(n, np.int64))
    np.save(f"{INST}/{scan}_unaligned_bbox.npy", np.zeros((0, 7), np.float32))
    np.save(f"{INST}/{scan}_aligned_bbox.npy", np.zeros((0, 7), np.float32))
    np.save(f"{INST}/{scan}_axis_align_matrix.npy", np.eye(4))
    scans.append(scan)
with open(f"{META}/test_list.txt", "w") as f:
    f.write("\n".join(scans) + "\n")
open(f"{META}/train_list.txt", "w").close(); open(f"{META}/val_list.txt", "w").close()
if not scans:
    print("no usable cylinders"); laspy.LasData(laspy.LasHeader(point_format=3,
        version="1.2")).write(OUT_LAZ); print("ARM_DONE"); sys.exit(0)

# 2. build points/*.bin + the test pkl IN-PROCESS, updating ONLY the test pkl.
# The stock tools/create_data_forainetv2.py also runs update_pkl_infos on the
# train/val pkls, which fail on our empty train/val splits. Replicate just
# create_info_file + the test-pkl update.
from mmdet3d.utils import register_all_modules
register_all_modules()
from converter_forainetv2 import create_info_file
from update_infos_to_v2 import update_pkl_infos
create_info_file(ROOT, "forainetv2", ROOT, workers=4)
update_pkl_infos("forainetv2", out_dir=ROOT,
                 pkl_path=os.path.join(ROOT, "forainetv2_oneformer3d_infos_test.pkl"))

# 3. one runner; iterate all scenes; collect UTM-restored labelled points
from mmengine.config import Config, ConfigDict
from mmengine.runner import Runner
import oneformer3d  # noqa: F401
cfg = Config.fromfile("configs/oneformer3d_qs_radius16_qp300_2many.py")
cfg.work_dir = "./work_dirs/arm"; cfg.load_from = CKPT
# Bound the row batch of the same exact nearest-neighbor calculation. The
# upstream 20,000-row cdist allocation can exceed 28 GiB on native-density ALS.
cfg.model.chunk = 2048
if cfg.model.get("test_cfg") is None:
    cfg.model.test_cfg = ConfigDict()
cfg.model.test_cfg["output_dir"] = cfg.work_dir
runner = Runner.from_cfg(cfg); runner.load_or_resume(); model = runner.model.eval()
import torch
def npy(x): return x.detach().cpu().numpy() if torch.is_tensor(x) else np.asarray(x)

XS, YS, ZS, INST_ID, BLK, SCORE = [], [], [], [], [], []
receipts = []
for block_i, data in enumerate(runner.test_dataloader):
    scan = scans[block_i]                                     # dataloader is ordered
    lidar_path = data["data_samples"][0].lidar_path
    if os.path.splitext(os.path.basename(lidar_path))[0] != scan or "test" not in lidar_path:
        raise ValueError("Unexpected input order or upstream inference route")
    full_scene = os.path.join(cfg.work_dir, scan + ".ply")
    if os.path.exists(full_scene):
        os.remove(full_scene)
    empty_sample_error = None
    try:
        with torch.no_grad():
            model.test_step(data, epoch=0)
    except AssertionError as error:
        if str(error) != EMPTY_SAMPLE_ERROR or not os.path.exists(full_scene):
            raise
        empty_sample_error = error
    # The returned sample describes only the last inner region. The saved PLY
    # is the complete scene, including background, with aligned point scores.
    pts = npy(data["inputs"]["points"][0] if isinstance(
        data["inputs"]["points"], list) else data["inputs"]["points"])[:, :3]
    staged = np.load(f"{INST}/{scan}_vert.npy")
    if not np.array_equal(staged, pts):
        raise ValueError("Test pipeline changed staged point order or coordinates")
    restored, per_point, sc = restore_native(
        pts, PlyData.read(full_scene)["vertex"].data, offsets[scan])
    if empty_sample_error is not None:
        # Upstream saves the valid all-background scene before a typed setter
        # rejects its None last-region return. All other failures remain fatal.
        validate_empty_sample_error(empty_sample_error, per_point)
    n = len(pts)
    XS.append(restored[:, 0]); YS.append(restored[:, 1])
    ZS.append(restored[:, 2]); INST_ID.append(per_point)
    BLK.append(np.full(n, block_i, np.int64))
    SCORE.append(sc)
    receipts.append(dict(scene=scan, lidar_path=lidar_path, points=n,
                         route="upstream_test", nn_chunk=cfg.model.chunk,
                         empty_sample_return=empty_sample_error is not None,
                         offset=offsets[scan].tolist(),
                         background=int((per_point == 0).sum()),
                         instances=int(len(np.unique(per_point[per_point > 0])))))
    print(f"{scan}: {n} pts, {len(np.unique(per_point[per_point>0]))} instances")

X = np.concatenate(XS); Y = np.concatenate(YS); Z = np.concatenate(ZS)
inst = np.concatenate(INST_ID); blk = np.concatenate(BLK); score = np.concatenate(SCORE)

# 4. write the merged UTM LAZ
h = laspy.LasHeader(point_format=3, version="1.2")
h.offsets = np.array([X.min(), Y.min(), Z.min()]); h.scales = [0.001, 0.001, 0.001]
las = laspy.LasData(h)
las.x, las.y, las.z = X, Y, Z
validate_las_ids(inst, blk)
las.point_source_id = inst.astype(np.uint16)
las.user_data = blk.astype(np.uint8)
las.add_extra_dim(laspy.ExtraBytesParams(name="ff3d_score", type=np.float32))
las.ff3d_score = score
las.write(OUT_LAZ)
with open(OUT_LAZ + ".json", "w") as stream:
    json.dump(receipts, stream, indent=2)
print(f"wrote {OUT_LAZ}: {len(X)} pts from {len(scans)} cylinders"); print("ARM_DONE")
