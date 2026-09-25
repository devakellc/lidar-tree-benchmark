#!/usr/bin/env python3
"""Fixed SAT pipeline with lossless pre-merge export for the development pilot."""
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time

import laspy
import numpy as np
from plyfile import PlyData, PlyElement

from fgiemit_sat_export import patch_sources, restore_native
from run_segmentanytree import SAT_HOME, LEGACY, _patch_eval_config


def main():
    inp, output = map(lambda p: Path(p).resolve(), sys.argv[1:3])
    if output.exists():
        raise ValueError("Never overwrite an existing SAT result")
    source = laspy.read(inp)
    if "tree_index" in source.point_format.dimension_names:
        raise ValueError("Reference annotations cannot be model inputs")
    home = Path(SAT_HOME)
    if not Path(LEGACY).exists():
        Path(LEGACY).parent.mkdir(parents=True, exist_ok=True)
        Path(LEGACY).symlink_to(home)
    work = output.parent / "sat_native"
    work.mkdir()
    src, dst = work / "input", work / "results"
    src.mkdir(); dst.mkdir()
    vertex = np.empty(len(source.points), dtype=[(k, "<f8") for k in "xyz"])
    for k in "xyz":
        vertex[k] = getattr(source, k)
    PlyData([PlyElement.describe(vertex, "vertex")]).write(src / "clip.ply")
    hashes = patch_sources(home)
    patched = work / "run_inference.sh"
    _patch_eval_config(str(home / "run_inference.sh"), str(patched))
    text = patched.read_text()
    marker = "# Rename the output files result_0.ply"
    if text.count(marker) != 1:
        raise ValueError("Unexpected SAT pipeline layout")
    # The unchanged native finalizer emits our complete sidecar. Do not invoke
    # the coordinate-string outer joins or quantized LAS writer downstream.
    patched.write_text(text.split(marker)[0])
    gpu = Path(__file__).resolve().parent
    env = dict(os.environ, FGIEMIT_NATIVE=str(work / "native"))
    env["PYTHONPATH"] = f"{gpu / 'sat_compat'}:{gpu}:{home}"
    started = time.monotonic()
    subprocess.run(["bash", str(patched), str(src), str(dst), "true"],
                   cwd=home, env=env, check=True)
    with np.load(work / "native_0.npz", allow_pickle=False) as native:
        labels = restore_native(source, native["xyz"], native["rows"], native["labels"])
        resources = {k: int(native[k]) for k in (
            "peak_cuda_allocated_bytes", "peak_cuda_reserved_bytes", "peak_host_rss_kib")}
    source.add_extra_dim(laspy.ExtraBytesParams(name="pred_instance", type=np.uint32))
    source.add_extra_dim(laspy.ExtraBytesParams(name="sat_row", type=np.uint32))
    source.pred_instance = labels
    source.sat_row = np.arange(len(labels), dtype=np.uint32)
    source.write(output)
    receipt = dict(source_patches=hashes, rows=len(labels), background=int(sum(labels == 0)),
        export="native_full_cloud_before_background_removal", wall_seconds=time.monotonic()-started,
        max_child_rss_kib=resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss, **resources)
    output.with_suffix(output.suffix + ".json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()
