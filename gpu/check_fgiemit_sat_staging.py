#!/usr/bin/env python3
"""CPU-only check of actual pinned SAT localization, reader and raw-cloud fusion."""
import ast
import json
from pathlib import Path
import tempfile
from unittest import mock

import laspy
import numpy as np
from plyfile import PlyData, PlyElement
import torch
from torch_geometric.data import Data

from fgiemit_sat_export import patch_sources, restore_native


home = Path("/opt/segment-any-tree")
writer_path = home / "torch_points3d/datasets/panoptic/treeins.py"
original_writers = writer_path.read_text()
patches = patch_sources(home)
from nibio_inference.pipeline_utm2local_parallel import modification_pipeline
from torch_points3d.datasets.segmentation.treeins import read_treeins_format
from torch_points3d.core.data_transform import PointCloudFusion
from nibio_inference.merge_pt_ss_is import MergePtSsIs


def load_writers(text):
    """Exercise the actual installed writer bodies without loading a model."""
    selected = []
    for node in ast.parse(text).body:
        if (isinstance(node, ast.FunctionDef) and node.name in
                ("to_ply", "to_eval_ply", "to_ins_ply")) or (
                isinstance(node, ast.Assign) and any(
                    isinstance(t, ast.Name) and t.id == "OBJECT_COLOR" for t in node.targets)):
            selected.append(node)
    namespace = dict(np=np, PlyData=PlyData, PlyElement=PlyElement)
    exec(compile(ast.Module(body=selected, type_ignores=[]), str(writer_path), "exec"), namespace)
    return namespace


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

    original = load_writers(original_writers)
    binary = load_writers(writer_path.read_text())
    xyz = np.column_stack((source.x, source.y, source.z)).astype(np.float32)
    semantics = np.array([0, 1, 1, 0])
    instances = np.array([-1, 7, 2, 32767])
    dummy = np.zeros(4, dtype=np.int16)
    for name, args in (("to_ply", (xyz, semantics)),
                       ("to_eval_ply", (xyz, instances, dummy)),
                       ("to_ins_ply", (xyz, instances))):
        before = [a.copy() for a in args]
        ascii_path, binary_path = directory / (name + ".ascii.ply"), directory / (name + ".binary.ply")
        original[name](*args, str(ascii_path))
        with mock.patch.object(np, "savetxt", side_effect=TypeError("injected WriteWrap failure")):
            try:
                original[name](*args, str(directory / "injected.ply"))
            except TypeError as error:
                assert str(error) == "injected WriteWrap failure"
            else:
                raise AssertionError("Original writer did not exercise the injected failure")
            binary[name](*args, str(binary_path))
        old, new = PlyData.read(ascii_path), PlyData.read(binary_path)
        assert old.text and not new.text
        np.testing.assert_array_equal(old["vertex"].data, new["vertex"].data)
        for value, unchanged in zip(args, before):
            np.testing.assert_array_equal(value, unchanged)

    # Match the failed scene's row count and original writer field dtypes.
    n = 3759456
    large = np.zeros((n, 3), dtype=np.float32)
    large[:, 0] = np.arange(n, dtype=np.float32) * .0001
    large[:, 1:] = [8, 1]
    large_labels = np.zeros(n, dtype=np.int16)
    large_path = directory / "full_size.binary.ply"
    with mock.patch.object(np, "savetxt", side_effect=AssertionError("ASCII path used")):
        binary["to_eval_ply"](large, large_labels, large_labels, str(large_path))
    decoded = PlyData.read(large_path)["vertex"].data
    assert len(decoded) == n
    for i, axis in enumerate("xyz"):
        np.testing.assert_array_equal(decoded[axis], large[:, i])
    assert not decoded["preds"].any() and not decoded["gt"].any()
    print(json.dumps(dict(status="passed", rows=4, duplicate_rows_preserved=True,
        historical_merge_rows=len(merged), background_preserved=True,
        reference_features_absent=True, binary_writers_checked=3,
        injected_ascii_failure_bypassed=True, full_size_binary_rows=n,
        patches=patches), indent=2))
