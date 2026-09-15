"""Validate the upstream full-scene output before restoring metric coordinates."""
import numpy as np

EMPTY_SAMPLE_ERROR = (
    "None should be a <class 'mmdet3d.structures.point_data.PointData'> "
    "but got <class 'NoneType'>"
)


def validate_empty_sample_error(error, labels):
    if not isinstance(error, AssertionError) or str(error) != EMPTY_SAMPLE_ERROR or np.any(labels != 0):
        raise ValueError("Unexpected native inference error; cannot accept saved output") from error


def native_scene_name(clip):
    from pathlib import Path
    # The pinned upstream predict() dispatches on 'test' in lidar_path.
    return "test_" + Path(clip).stem


def restore_native(points, vertices, offset):
    xyz = np.column_stack([vertices[key] for key in ("x", "y", "z")])
    if xyz.shape != points.shape or not np.allclose(xyz, points, atol=1e-5, rtol=0):
        raise ValueError("Full-scene output changed point count, order, or coordinates")
    labels = np.asarray(vertices["instance_pred"])
    if np.any(~np.isfinite(labels) | (labels < -1) | (labels != np.floor(labels))):
        raise ValueError("Expected upstream -1 background and zero-based instance IDs")
    ids = labels.astype(np.int64) + 1
    scores = np.asarray(vertices["score"], dtype=np.float32)
    if np.any(~np.isfinite(scores)) or np.any((ids > 0) & (scores < 0)):
        raise ValueError("Invalid full-scene per-point confidence")
    scores = np.where(ids > 0, scores, 0)
    return xyz.astype(np.float64) + offset, ids, scores


def validate_las_ids(ids, blocks):
    for values, limit, name in ((ids, 65535, "instance"), (blocks, 255, "block")):
        values = np.asarray(values)
        if np.any(~np.isfinite(values) | (values < 0) | (values > limit) |
                  (values != np.floor(values))):
            raise ValueError(f"{name} IDs cannot be represented losslessly in LAS")


def scene_output(source, labels, scores):
    """Attach native predictions without reconstructing or duplicating input rows."""
    import laspy
    n = len(source.points)
    labels = np.asarray(labels)
    scores = np.asarray(scores)
    if labels.shape != (n,) or scores.shape != (n,):
        raise ValueError("Whole-scene output requires one label and score per input row")
    if n > np.iinfo(np.uint32).max:
        raise ValueError("Source row IDs exceed the supported LAS range")
    validate_las_ids(labels, np.zeros(n, dtype=np.uint8))
    if (np.any(~np.isfinite(scores)) or np.any((labels > 0) &
            ((scores < 0) | (scores > np.finfo(np.float32).max)))):
        raise ValueError("Invalid whole-scene confidence")
    for name in ("ff3d_score", "ff3d_row"):
        if name in source.point_format.extra_dimension_names:
            raise ValueError("Whole-scene input already contains prediction metadata")
    source.point_source_id = labels.astype(np.uint16)
    source.user_data = np.zeros(n, dtype=np.uint8)
    source.add_extra_dim(laspy.ExtraBytesParams(name="ff3d_score", type=np.float32))
    source.add_extra_dim(laspy.ExtraBytesParams(name="ff3d_row", type=np.uint32))
    source.ff3d_score = np.where(labels > 0, scores, 0)
    source.ff3d_row = np.arange(n, dtype=np.uint32)
    return source
