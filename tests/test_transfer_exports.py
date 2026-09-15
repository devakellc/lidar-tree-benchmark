"""CPU-only regressions for frozen transfer export contracts."""
import importlib.util
from pathlib import Path
import unittest
from unittest import mock
import sys
import tempfile
import json
import types
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ff = load("ff_export", "gpu/forestformer3d-sm120/ff3d_export.py")
ti = load("ti_export", "gpu/treeisonet_export.py")


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.points = np.array([[0, 0, 0], [0, 0, 10], [2, 3, 5]], dtype=np.float32)
        self.vertices = dict(zip(("x", "y", "z"), self.points.T))
        self.vertices.update(instance_pred=np.array([-1, 0, 8]),
                             score=np.array([-1, .7, .9]))

    def test_native_route_background_zero_based_ids_and_point_scores(self):
        self.assertEqual(ff.native_scene_name("/tmp/cyl_000.laz"), "test_cyl_000")
        xyz, labels, scores = ff.restore_native(self.points, self.vertices, [100, 200, -2])
        np.testing.assert_array_equal(xyz, self.points + [100, 200, -2])
        np.testing.assert_array_equal(labels, [0, 1, 9])
        np.testing.assert_allclose(scores, [0, .7, .9])

    def test_last_region_truncation_and_point_permutation_rejected(self):
        with self.assertRaisesRegex(ValueError, "count, order"):
            ff.restore_native(self.points[:2], self.vertices, [0, 0, 0])
        with self.assertRaisesRegex(ValueError, "count, order"):
            ff.restore_native(self.points[[1, 0, 2]], self.vertices, [0, 0, 0])

    def test_float64_restoration_preserves_submeter_detail_at_projected_offsets(self):
        points = np.array([[.125, .125, 2]], dtype=np.float32)
        vertex = dict(x=points[:, 0], y=points[:, 1], z=points[:, 2],
                      instance_pred=np.array([0]), score=np.array([.5]))
        xyz, _, _ = ff.restore_native(points, vertex, [600000, 5300000, 100])
        self.assertEqual(xyz.dtype, np.float64)
        np.testing.assert_array_equal(xyz, [[600000.125, 5300000.125, 102]])

    def test_only_known_empty_return_error_accepts_valid_all_background_scene(self):
        error = AssertionError(ff.EMPTY_SAMPLE_ERROR)
        ff.validate_empty_sample_error(error, np.zeros(3, dtype=int))
        for failure, labels in ((error, np.array([0, 1])),
                                (AssertionError("different failure"), np.zeros(2)),
                                (RuntimeError(ff.EMPTY_SAMPLE_ERROR), np.zeros(2))):
            with self.assertRaises(ValueError):
                ff.validate_empty_sample_error(failure, labels)

    def test_las_label_bounds_are_not_clipped(self):
        ff.validate_las_ids([0, 65535], [0, 255])
        for ids, blocks in (([65536], [0]), ([1], [256]), ([-1], [0]), ([1.2], [0])):
            with self.assertRaises(ValueError):
                ff.validate_las_ids(ids, blocks)

    def test_physical_height_not_min_shift_and_unsupported_background(self):
        points = np.array([[0, 0, -1], [0, 0, 1.5], [0, 0, 2], [0, 0, 30]])
        support = ti.prediction_support(points, [128]*3, [.1, .1, .2])
        np.testing.assert_array_equal(support, [True, True, True, False])
        np.testing.assert_array_equal(ti.canopy_labels(points, [1]*4, support, 2), [0, 0, 1, 0])

    def test_per_block_support_is_translation_and_order_invariant(self):
        points = np.array([[0, 0, 0], [0, 0, 25.6], [13, 0, 50], [13, 0, 75.5]])
        support = ti.prediction_support(points, [128]*3, [.1, .1, .2])
        np.testing.assert_array_equal(support, [True, False, True, True])
        order = [2, 0, 3, 1]
        np.testing.assert_array_equal(ti.prediction_support(points[order] + [100, 200, -8],
                                      [128]*3, [.1, .1, .2]), support[order])

    def test_duplicates_and_vertical_overlap_keep_row_identity(self):
        points = np.array([[1, 2, 3], [1, 2, 3], [1, 2, 15]])
        labels = ti.canopy_labels(points, [1, 2, 3], [True]*3, 2)
        np.testing.assert_array_equal(labels, [1, 2, 3])
        with self.assertRaises(ValueError):
            ti.canopy_labels(points, [1, 2], [True]*3, 2)


class UpstreamSupportTests(unittest.TestCase):
    def test_nearest_neighbor_row_batch_preserves_indices_and_ties(self):
        try:
            import torch
        except ImportError:
            self.skipTest("Optional torch environment is not installed")
        torch.manual_seed(9)
        source = torch.rand(128, 3)
        source[1] = source[0]
        query = torch.cat([source[:4], torch.rand(61, 3)])
        full = torch.cdist(query, source).argmin(1)
        batched = torch.cat([torch.cdist(part, source).argmin(1)
                             for part in query.split(32)])
        torch.testing.assert_close(full, batched, rtol=0, atol=0)
        self.assertEqual(int(full[0]), 0)

    def test_actual_treeoff_leaves_unsupported_points_at_label_one(self):
        path = ROOT / "gpu/TreeAIBox/modules/treeisonet/treeOff.py"
        if not path.exists():
            self.skipTest("Optional pinned TreeAIBox checkout is not installed")
        try:
            import torch
            import numpy_indexed  # noqa: F401
        except ImportError:
            self.skipTest("Run with the existing TreeisoNet environment for upstream integration")
        upstream = load("treeoff", str(path))

        class Stub(torch.nn.Module):
            def __init__(self, **kwargs):
                super().__init__()

            def forward(self, x):
                return torch.zeros_like(x)

        config = dict(voxel_number_in_block=[2, 2, 2], voxel_resolution_in_meter=[1, 1, 1],
                      patch_size=1, decoder_dim=1, channel_dims=[1], num_heads=[1],
                      MLP_ratios=[1], qkv_bias=False, depths=[1], SR_ratios=[1])
        points = np.array([[0., 0, 0], [1, 1, 1], [1, 1, 3]])
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "model.json"
            cfg.write_text(json.dumps(dict(model=config)))
            module = types.SimpleNamespace(Segformer=Stub)
            with mock.patch.dict(sys.modules, {"vox3DSegFormerRegression": module}), \
                    mock.patch.object(torch, "load", return_value={}):
                raw = upstream.treeOff(str(cfg), points, np.array([[.5, .5, 1]]),
                                       "unused", use_cuda=False)
        np.testing.assert_array_equal(raw, [1, 1, 1])
        support = ti.prediction_support(points, [2]*3, [1]*3)
        np.testing.assert_array_equal(support, [True, True, False])
        np.testing.assert_array_equal(ti.canopy_labels(points, raw, support, 0), [1, 1, 0])


if __name__ == "__main__":
    unittest.main()
