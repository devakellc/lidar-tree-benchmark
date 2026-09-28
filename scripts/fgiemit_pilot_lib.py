"""Strict local-frame output admission and unchanged fixed instance filtering."""
import numpy as np


def aligned_labels(source, predicted, arm):
    if len(source.points) != len(predicted.points):
        raise ValueError("Prediction coverage differs from retained source rows")
    for name in ("X", "Y", "Z", "source_row", "return_number", "number_of_returns"):
        if not np.array_equal(getattr(source, name), getattr(predicted, name)):
            raise ValueError(f"Prediction changed original {name}")
    if (not np.array_equal(source.header.scales, predicted.header.scales) or
            not np.array_equal(source.header.offsets, predicted.header.offsets) or
            predicted.header.parse_crs() != source.header.parse_crs()):
        raise ValueError("Prediction changed coordinate frame or precision")
    if arm == "segmentanytree":
        rows, labels = predicted.sat_row, predicted.pred_instance
        scores = None
    elif arm == "forestformer3d":
        rows, labels = predicted.ff3d_row, predicted.point_source_id
        scores = np.asarray(predicted.ff3d_score)
        if (np.any(np.asarray(predicted.user_data) != 0) or not np.isfinite(scores).all() or
                np.any(scores < 0) or np.any(scores[np.asarray(labels) == 0] != 0)):
            raise ValueError("Invalid whole-scene FF3D confidence or outer blocks")
    else:
        raise ValueError("Unknown instance arm")
    if not np.array_equal(rows, np.arange(len(source.points))):
        raise ValueError("Prediction row receipt is incomplete or reordered")
    labels = np.asarray(labels)
    if not np.isfinite(labels).all() or np.any(labels < 0) or np.any(labels != np.floor(labels)):
        raise ValueError("Invalid instance identities")
    return labels.astype(np.int64), scores


def fixed_filter(labels, z, scores=None):
    labels, z = np.asarray(labels), np.asarray(z)
    if labels.shape != z.shape or not np.isfinite(z).all():
        raise ValueError("Invalid filter substrate")
    positive = np.flatnonzero(labels > 0)
    order = positive[np.argsort(labels[positive], kind="stable")]
    ids, starts, counts = np.unique(labels[order], return_index=True, return_counts=True)
    result = np.zeros(labels.shape, dtype=np.int64)
    confidence = {}
    if not len(ids):
        return result, confidence
    extents = np.maximum.reduceat(z[order], starts) - np.minimum.reduceat(z[order], starts)
    accepted = (counts >= 40) & (extents >= 1.5)
    sums = np.add.reduceat(np.asarray(scores)[order], starts) if scores is not None else None
    for i in np.flatnonzero(accepted):
        result[order[starts[i]:starts[i] + counts[i]]] = ids[i]
        confidence[int(ids[i])] = float(sums[i] / counts[i]) if sums is not None else int(counts[i])
    return result, confidence
