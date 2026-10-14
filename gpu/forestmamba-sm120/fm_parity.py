#!/usr/bin/env python
"""Port check: this sm_120 ForestMamba run against the authors' own predictions.

The authors published their predictions of the same v6 checkpoint for the
FOR-instanceV2 test scenes (x, y, z, predictions and reference labels). Each
scene's points are staged as published (they are already local coordinates),
with zero labels as the NEON arm stages a clip, and run once through fm_arm's
staging, strict model load and test route. Both prediction sets are scored
with the authors' evaluator (tools/eval_predictions.py) against the same
reference labels, and our instances are matched to theirs.

Run from the ForestMamba checkout root:
    python fm_parity.py <checkpoint> <out_dir> <seed> <authors_scene.ply>...
Writes <out_dir>/<scene>.ply (our predictions with the authors' reference
labels) and <out_dir>/parity.json.
"""
import json
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fm_arm  # noqa: E402
from fm_export import native_scene_name, restore_dense  # noqa: E402

FIELDS = ("prec", "rec", "f1", "cov", "iou_g", "iou_w", "iou_l", "miou", "n_trees")


def instance_agreement(ours, theirs):
    """Their instances recovered by ours: best-IoU match per authors' instance."""
    from eval_predictions import _iou_matrix, _make_contiguous_labels
    a, ia = _make_contiguous_labels(np.asarray(ours, np.int64))
    b, ib = _make_contiguous_labels(np.asarray(theirs, np.int64))
    best = (_iou_matrix(a, b, len(ia), len(ib)).max(axis=0) if len(ia) and len(ib)
            else np.zeros(len(ib)))
    both = (a > 0) == (b > 0)
    return dict(ours=int(len(ia)), theirs=int(len(ib)),
                matched_at_0_5=int((best >= .5).sum()),
                mean_best_iou=float(best.mean()) if len(best) else None,
                tree_background_agreement=float(both.mean()))


def main(argv):
    checkpoint, out_dir, seed = argv[1], argv[2], int(argv[3])
    scenes = argv[4:]
    sys.path.insert(0, os.getcwd())
    sys.path.insert(0, os.path.join(os.getcwd(), "tools"))
    from plyfile import PlyData, PlyElement
    from eval_predictions import process_single_file
    from mmdet3d.utils import register_all_modules
    register_all_modules()
    os.makedirs(out_dir, exist_ok=True)
    published = {}
    for path in scenes:
        published[native_scene_name(path)] = (path, PlyData.read(path)["vertex"].data)
    scans = list(published)
    fm_arm.stage_scenes([(scan, np.column_stack([published[scan][1][k] for k in "xyz"]))
                         for scan in scans])
    runner, model = fm_arm.build_model(checkpoint)
    rows = []
    for scan, points, vertices, empty, run in fm_arm.infer_scenes(runner, model, scans, seed):
        path, theirs = published[scan]
        _, ids, scores = restore_dense(points, vertices, np.zeros(3))   # contract check
        ours = np.empty(len(points), dtype=[(k, "f4") for k in "xyz"] +
                        [("semantic_pred", "i4"), ("instance_pred", "i4"), ("score", "f4"),
                         ("semantic_gt", "i4"), ("instance_gt", "i4")])
        for k in "xyz":
            ours[k] = theirs[k]
        ours["semantic_pred"] = vertices["semantic_pred"]
        ours["instance_pred"] = np.where(ids > 0, ids, -1)
        ours["score"] = scores
        ours["semantic_gt"], ours["instance_gt"] = theirs["semantic_gt"], theirs["instance_gt"]
        mine = os.path.join(out_dir, os.path.basename(path))
        PlyData([PlyElement.describe(ours, "vertex")], text=False).write(mine)
        score = lambda f: {k: process_single_file(f)[k] for k in FIELDS}   # noqa: E731
        rows.append(dict(scene=os.path.basename(path), points=int(len(points)),
                         authors=score(path), this_port=score(mine),
                         agreement=instance_agreement(ours["instance_pred"],
                                                      theirs["instance_pred"]),
                         infer_seconds=run["infer_seconds"]))
        print(scan, json.dumps(rows[-1]["this_port"]), flush=True)
    report = dict(seed=seed, checkpoint=os.path.basename(checkpoint), config=fm_arm.CONFIG,
                  versions=fm_arm.versions(), created=time.strftime("%Y-%m-%d %H:%M:%S"),
                  scenes=rows)
    with open(os.path.join(out_dir, "parity.json"), "w") as stream:
        json.dump(report, stream, indent=2, default=float)
    print("PARITY_DONE")


if __name__ == "__main__":
    main(sys.argv)
