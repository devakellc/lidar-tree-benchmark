"""Validate ForestMamba's saved full scene before restoring metric coordinates.

ForestMamba is a fork of the ForestFormer3D code and takes the same native
`test_*` route, so the scene name, the empty-return check and the row-indexed
whole-scene LAZ (ff3d_score / ff3d_row) are the ForestFormer3D ones. Only the
saved labels differ: ForestMamba writes -1 background and dense 1..M instance
IDs, where ForestFormer3D writes -1 and zero-based IDs.
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "forestformer3d-sm120"))
from ff3d_export import (native_scene_name, scene_output,  # noqa: E402,F401
                         validate_empty_sample_error, EMPTY_SAMPLE_ERROR)


NOISE_CLASSES = (7, 18)                 # ASPRS low and high noise


def stage_frame(xyz, classification):
    """Rows the model sees, the staging origin and the rule that set its z.

    Classified noise is not scene geometry: those rows stay out of the model's
    scene and are exported as background. ForestMamba reads staged z as height
    (its canopy-peak queries and the decoder's vertical ordering), so z counts
    from the lowest ground return (class 2), or from the lowest remaining
    return where a clip has no ground. x and y are centred on the kept rows'
    mean so float32 keeps centimetre precision.
    """
    xyz = np.asarray(xyz, dtype=np.float64)
    cls = np.asarray(classification)
    keep = ~np.isin(cls, NOISE_CLASSES)
    if not keep.any():
        return keep, np.zeros(3), "no non-noise return"
    ground = keep & (cls == 2)
    if ground.any():
        z0, rule = xyz[ground, 2].min(), "lowest ground return"
    else:
        z0, rule = xyz[keep, 2].min(), "lowest non-noise return"
    return keep, np.array([xyz[keep, 0].mean(), xyz[keep, 1].mean(), z0]), rule


def expand_to_rows(keep, ids, scores):
    """Per-row IDs and scores: the staged rows' predictions, background elsewhere."""
    keep = np.asarray(keep, dtype=bool)
    if len(ids) != keep.sum() or len(scores) != keep.sum():
        raise ValueError("Predictions do not cover the staged rows exactly")
    out_ids = np.zeros(len(keep), dtype=np.int64)
    out_scores = np.zeros(len(keep), dtype=np.float32)
    out_ids[keep], out_scores[keep] = ids, scores
    return out_ids, out_scores


def restore_dense(points, vertices, offset):
    """Saved PLY vertices -> (float64 xyz + offset, IDs with 0 background, scores)."""
    xyz = np.column_stack([vertices[key] for key in ("x", "y", "z")])
    if xyz.shape != points.shape or not np.allclose(xyz, points, atol=1e-5, rtol=0):
        raise ValueError("Full-scene output changed point count, order, or coordinates")
    labels = np.asarray(vertices["instance_pred"])
    if np.any(~np.isfinite(labels) | (labels != np.floor(labels)) |
              ((labels < 1) & (labels != -1))):
        raise ValueError("Expected -1 background and positive integer instance IDs")
    ids = np.where(labels > 0, labels, 0).astype(np.int64)
    present = np.unique(ids[ids > 0])
    if not np.array_equal(present, np.arange(1, len(present) + 1)):
        raise ValueError("Instance IDs are not the dense 1..M range")
    scores = np.asarray(vertices["score"], dtype=np.float32)
    if np.any(~np.isfinite(scores)) or np.any((ids > 0) & (scores < 0)):
        raise ValueError("Invalid full-scene per-point confidence")
    scores = np.where(ids > 0, scores, 0).astype(np.float32)
    return xyz.astype(np.float64) + offset, ids, scores
