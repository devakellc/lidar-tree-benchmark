#!/usr/bin/env python3
"""CPU-only check of actual pinned SAT localization, reader and raw-cloud fusion."""
import json
from pathlib import Path
import tempfile

import laspy
import numpy as np
from plyfile import PlyData, PlyElement
import torch
from torch_geometric.data import Data

from fgiemit_sat_export import patch_sources, restore_native


home = Path("/opt/segment-any-tree")
patches = patch_sources(home)
from nibio_inference.pipeline_utm2local_parallel import modification_pipeline
from torch_points3d.datasets.segmentation.treeins import read_treeins_format
from torch_points3d.core.data_transform import PointCloudFusion
from nibio_inference.merge_pt_ss_is import MergePtSsIs

with tempfile.TemporaryDirectory() as tmp:
    directory = Path(tmp)
    source = laspy.LasData(laspy.LasHeader(point_format=3, version="1.2"))
    source.x = np.array([-10., -10., -10., 12.])
    source.y = np.array([8., 8., 8., 14.])
    source.z = np.array([1., 1., 2., 7.])
    vertex = np.empty(4, dtype=[(k, "<f8") for k in "xyz"])
    for k in "xyz":
        vertex[k] = getattr(source, k)
    inp, local = directory / "clip.ply", directory / "clip_out.ply"
    PlyData([PlyElement.describe(vertex, "vertex")]).write(inp)
    modification_pipeline(str(inp), str(local), str(directory / "min.json"), True)
    xyz, sem, labels = read_treeins_format(str(local))
    data = Data(pos=xyz, y=sem, fgiemit_row=torch.arange(4))
    area = PointCloudFusion()([[data]])[0]
    result = restore_native(source, area.pos.numpy(), area.fgiemit_row.numpy(), [-1, 7, 2, -1])
    np.testing.assert_array_equal(result, [0, 8, 3, 0])
    assert not sem.any() and not labels.any()
    # Reproduce why the historical final merge cannot establish row identity.
    local_vertex = PlyData.read(local)["vertex"].data
    for name, indices, predictions in (("semantic", [0, 1, 2, 3], [0, 1, 1, 0]),
                                        ("instance", [1, 2], [7, 2])):
        v = np.empty(len(indices), dtype=[(k, "<f4") for k in "xyz"] + [("preds", "<i4")])
        for k in "xyz":
            v[k] = local_vertex[k][indices]
        v["preds"] = predictions
        PlyData([PlyElement.describe(v, "vertex")]).write(directory / f"{name}.ply")
    (directory / "clip_out_min_values.json").write_text((directory / "min.json").read_text())
    merged = MergePtSsIs(str(local), str(directory / "semantic.ply"),
                         str(directory / "instance.ply"), None).merge()
    assert len(merged) == 6
    print(json.dumps(dict(status="passed", rows=4, duplicate_rows_preserved=True,
        historical_merge_rows=len(merged), background_preserved=True,
        reference_features_absent=True, patches=patches), indent=2))
