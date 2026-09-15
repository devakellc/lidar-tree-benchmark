"""Prediction support and height-frame checks for the pinned TreeisoNet model."""
import numpy as np


def prediction_support(points, blocks, resolution):
    """Mirror treeOff's XY blocks and per-block voxel extent, without inference."""
    points = np.asarray(points)
    blocks = np.asarray(blocks)
    resolution = np.asarray(resolution)
    if points.ndim != 2 or points.shape[1] != 3 or not np.all(np.isfinite(points)):
        raise ValueError("Expected finite XYZ points")
    if blocks.shape != (3,) or resolution.shape != (3,) or np.any(blocks <= 0) or np.any(resolution <= 0):
        raise ValueError("Expected positive three-dimensional block/resolution")
    if len(points) == 0:
        return np.zeros(0, dtype=bool)
    ij = np.floor((points[:, :2] - points.min(0)[:2]) / resolution[:2] / blocks[:2])
    _, group = np.unique(ij, axis=0, return_inverse=True)
    mins = np.full((group.max() + 1, 3), np.inf)
    np.minimum.at(mins, group, points)
    ijk = np.floor((points - mins[group]) / resolution)
    return np.all((ijk >= 0) & (ijk < blocks), axis=1)


def canopy_labels(xyz, ids, support, hmin):
    ids = np.asarray(ids).reshape(-1)
    support = np.asarray(support, dtype=bool)
    if len(ids) != len(xyz) or support.shape != ids.shape:
        raise ValueError("Labels/support must match every input point")
    if np.any(~np.isfinite(ids) | (ids < 0) | (ids != np.floor(ids))):
        raise ValueError("Expected non-negative integer instance IDs")
    if not np.isfinite(hmin):
        raise ValueError("Height cutoff must be finite")
    return np.where(support & (xyz[:, 2] >= hmin), ids, 0).astype(np.int32)
