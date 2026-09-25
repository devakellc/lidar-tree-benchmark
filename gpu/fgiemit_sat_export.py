"""Export SAT's existing full-cloud labels with explicit ordered row identity."""
import hashlib
import os
from pathlib import Path
import resource

import numpy as np


def patch_sources(home):
    """Patch export bookkeeping and visualization encoding in an ephemeral container."""
    dataset = home / "torch_points3d/datasets/segmentation/treeins.py"
    tracker = home / "torch_points3d/metrics/panoptic_tracker_pointgroup_treeins.py"
    writers = home / "torch_points3d/datasets/panoptic/treeins.py"
    marker = "                data = Data(pos=xyz, y=semantic_labels)"
    export_marker = "                    things_idx = full_ins_pred != -1"
    replacements = {
        dataset: (marker, marker + "\n                data.fgiemit_row = torch.arange(len(xyz))", 2),
        tracker: (export_marker,
            "                    from fgiemit_sat_export import save_native\n"
            "                    save_native(test_area_i, full_ins_pred, i)\n" + export_marker, 1),
        # These visualization files are never read by the native-label path.
        # Keep their arrays/schema unchanged while avoiding numpy.savetxt's
        # per-row ASCII writer, which crashed before export on plot 1019.
        writers: ("PlyData([el], text=True).write(file)",
                  "PlyData([el], text=False, byte_order='<').write(file)", 3),
    }
    hashes = {}
    for path, (old, new, count) in replacements.items():
        text = path.read_text()
        if text.count(old) != count or "fgiemit" in text:
            raise ValueError("Unexpected pinned SAT source; refuse an unreviewed patch")
        changed = text.replace(old, new)
        compile(changed, str(path), "exec")
        hashes[str(path.relative_to(home))] = dict(
            before=hashlib.sha256(text.encode()).hexdigest(),
            after=hashlib.sha256(changed.encode()).hexdigest())
        path.write_text(changed)
    return hashes


def save_native(area, labels, index):
    """Called after SAT's own interpolation/filtering, before background removal."""
    import torch
    path = os.environ["FGIEMIT_NATIVE"] + f"_{index}.npz"
    if Path(path).exists():
        raise ValueError("Native SAT receipt already exists")
    np.savez(path, xyz=area.pos.detach().cpu().numpy(),
        rows=area.fgiemit_row.detach().cpu().numpy(),
        labels=labels.detach().cpu().numpy(),
        peak_cuda_allocated_bytes=torch.cuda.max_memory_allocated(),
        peak_cuda_reserved_bytes=torch.cuda.max_memory_reserved(),
        peak_host_rss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)


def restore_native(source, xyz, rows, labels):
    """Prove complete ordered native support; never transfer nearest labels."""
    n = len(source.points)
    rows, xyz, labels = np.asarray(rows), np.asarray(xyz), np.asarray(labels)
    if rows.shape != (n,) or not np.array_equal(rows, np.arange(n)):
        raise ValueError("SAT native rows are incomplete, duplicated or reordered")
    original = np.column_stack((source.x, source.y, source.z))
    expected = (original - original.min(axis=0)).astype(np.float32)
    if xyz.shape != expected.shape or not np.array_equal(xyz, expected):
        raise ValueError("SAT native coordinates differ from the staged source rows")
    if (labels.shape != (n,) or not np.isfinite(labels).all() or
            np.any(labels != np.floor(labels)) or np.any(labels < -1) or
            np.any(labels >= np.iinfo(np.uint32).max)):
        raise ValueError("Invalid native SAT instance labels")
    return (labels.astype(np.int64) + 1).astype(np.uint32)
