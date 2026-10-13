"""CPU-only regressions for frozen transfer export contracts."""
import importlib.util
from pathlib import Path
import unittest
from unittest import mock
import sys
import tempfile
import json
import types
import ast
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ff = load("ff_export", "gpu/forestformer3d-sm120/ff3d_export.py")
ti = load("ti_export", "gpu/treeisonet_export.py")
fm = load("fm_export", "gpu/forestmamba-sm120/fm_export.py")
fmck = load("fm_checkpoint", "gpu/forestmamba-sm120/fm_checkpoint.py")


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
    def test_native_mask_policy_preserves_background_and_overwrites_accepted_overlap(self):
        path = ROOT / "gpu/store/forestformer3d/ForestFormer3D/oneformer3d/oneformer3d.py"
        if not path.exists():
            self.skipTest("Optional pinned ForestFormer3D checkout is not installed")
        tree = ast.parse(path.read_text())
        cls = next(node for node in tree.body if isinstance(node, ast.ClassDef)
                   and node.name == "ForAINetV2OneFormer3D_XAwarequery")
        fn = next(node for node in cls.body if isinstance(node, ast.FunctionDef)
                  and node.name == "merge_overlapping_instances_by_score_speedup")
        fn.decorator_list = []
        scope = dict(np=np)
        exec(compile(ast.Module(body=[fn], type_ignores=[]), str(path), "exec"), scope)
        merge = scope[fn.name]
        labels, _, scores = merge(np.zeros(6), [([0, 1], 1, .9), ([1, 2, 3, 4], 2, .8)])
        np.testing.assert_array_equal(labels, [1, 2, 2, 2, 2, -1])
        np.testing.assert_allclose(scores, [.9, .8, .8, .8, .8, -1])
        labels, _, _ = merge(np.zeros(4), [([0, 1], 1, .9), ([1, 2, 3], 2, .8)])
        np.testing.assert_array_equal(labels, [1, 1, -1, -1])

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


class WholeSceneTests(unittest.TestCase):
    def source(self, empty=False):
        import laspy
        header = laspy.LasHeader(point_format=3, version="1.2")
        header.scales = [.001, .002, .003]
        header.offsets = [600000, 5300000, 100]
        source = laspy.LasData(header)
        if not empty:
            source.X = [123, 123, 123, 456]
            source.Y = [12, 12, 12, 34]
            source.Z = [0, 0, 6000, 3000]
            source.classification = [2, 1, 1, 1]
        return source

    def test_exact_las_roundtrip_preserves_duplicates_vertical_rows_and_background(self):
        import laspy
        source = self.source()
        xyz = np.column_stack([source.X, source.Y, source.Z])
        out = ff.scene_output(source, [0, 1, 2, 3], [-1, .8, .7, .6])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "scene.laz"
            out.write(path)
            restored = laspy.read(path)
        np.testing.assert_array_equal(np.column_stack([restored.X, restored.Y, restored.Z]), xyz)
        np.testing.assert_array_equal(restored.header.scales, [.001, .002, .003])
        np.testing.assert_array_equal(restored.header.offsets, [600000, 5300000, 100])
        np.testing.assert_array_equal(restored.classification, [2, 1, 1, 1])
        np.testing.assert_array_equal(restored.ff3d_row, [0, 1, 2, 3])
        np.testing.assert_array_equal(restored.point_source_id, [0, 1, 2, 3])
        np.testing.assert_array_equal(restored.user_data, [0]*4)
        np.testing.assert_allclose(restored.ff3d_score, [0, .8, .7, .6])

    def test_incomplete_invalid_and_prelabelled_exports_fail(self):
        for labels, scores in (([1]*3, [1]*4), ([1]*4, [1]*3),
                               ([1, 2, 65536, 0], [1]*4),
                               ([1]*4, [1, -1, 1, 1]),
                               ([1]*4, [1, np.nan, 1, 1]),
                               ([1]*4, [1, 1e40, 1, 1])):
            with self.assertRaises(ValueError):
                ff.scene_output(self.source(), labels, scores)
        out = ff.scene_output(self.source(), [0]*4, [-1]*4)
        with self.assertRaisesRegex(ValueError, "already contains"):
            ff.scene_output(out, [0]*4, [0]*4)

    def test_empty_scene_and_all_background_are_valid(self):
        import laspy
        out = ff.scene_output(self.source(empty=True), [], [])
        self.assertEqual(len(out.points), 0)
        self.assertIn("ff3d_row", out.point_format.extra_dimension_names)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "empty.laz"
            out.write(path)
            restored = laspy.read(path)
            self.assertEqual(len(restored.points), 0)
            self.assertIn("ff3d_score", restored.point_format.extra_dimension_names)
            self.assertIn("ff3d_row", restored.point_format.extra_dimension_names)
        out = ff.scene_output(self.source(), [0]*4, [-1]*4)
        np.testing.assert_array_equal(out.ff3d_score, [0]*4)


class ForestMambaExportTests(unittest.TestCase):
    """ForestMamba saves -1 background and dense 1..M instance IDs."""

    def setUp(self):
        self.points = np.array([[0, 0, 0], [0, 0, 10], [2, 3, 5], [2, 3, 6]],
                               dtype=np.float32)

    def vertices(self, labels, scores=None):
        vertex = dict(zip(("x", "y", "z"), self.points.T))
        vertex.update(instance_pred=np.asarray(labels),
                      score=np.asarray([.5] * len(labels) if scores is None else scores,
                                       dtype=np.float32))
        return vertex

    def test_dense_ids_are_kept_and_background_becomes_zero(self):
        xyz, ids, scores = fm.restore_dense(
            self.points, self.vertices([-1, 1, 2, 2], [0, .7, .9, .9]), [100, 200, -2])
        np.testing.assert_array_equal(ids, [0, 1, 2, 2])     # not shifted like FF3D's IDs
        np.testing.assert_allclose(scores, [0, .7, .9, .9])
        self.assertEqual(xyz.dtype, np.float64)
        np.testing.assert_array_equal(xyz, self.points + [100, 200, -2])

    def test_background_scores_are_zeroed(self):
        _, _, scores = fm.restore_dense(
            self.points, self.vertices([-1, -1, 1, 1], [-1, 3, .4, .4]), [0, 0, 0])
        np.testing.assert_allclose(scores, [0, 0, .4, .4])

    def test_zero_ids_ids_below_minus_one_and_fractions_are_rejected(self):
        for labels in ([0, 1, 1, 1], [-2, 1, 1, 1], [-1, 1.5, 1, 1]):
            with self.assertRaisesRegex(ValueError, "background"):
                fm.restore_dense(self.points, self.vertices(labels), [0, 0, 0])

    def test_gaps_in_the_dense_numbering_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "not the dense"):
            fm.restore_dense(self.points, self.vertices([-1, 1, 3, 3]), [0, 0, 0])

    def test_point_count_and_order_changes_are_rejected(self):
        vertex = self.vertices([-1, 1, 2, 2])
        with self.assertRaisesRegex(ValueError, "count, order"):
            fm.restore_dense(self.points[:3], vertex, [0, 0, 0])
        with self.assertRaisesRegex(ValueError, "count, order"):
            fm.restore_dense(self.points[[1, 0, 2, 3]], vertex, [0, 0, 0])

    def test_invalid_confidence_is_rejected(self):
        for scores in ([0, -.1, .5, .5], [0, np.nan, .5, .5], [np.inf, .5, .5, .5]):
            with self.assertRaisesRegex(ValueError, "confidence"):
                fm.restore_dense(self.points, self.vertices([-1, 1, 2, 2], scores), [0, 0, 0])

    def test_all_background_scene_is_valid(self):
        _, ids, scores = fm.restore_dense(self.points, self.vertices([-1] * 4, [0] * 4),
                                          [0, 0, 0])
        np.testing.assert_array_equal(ids, [0] * 4)
        np.testing.assert_array_equal(scores, [0] * 4)

    def test_noise_returns_leave_the_scene_and_ground_sets_the_height_origin(self):
        xyz = np.array([[10, 20, 353.5], [11, 21, 383.5], [12, 22, 400], [13, 23, 384],
                        [14, 24, 900]], dtype=np.float64)
        cls = np.array([7, 2, 5, 2, 18])               # low noise, ground, veg, ground, high noise
        keep, offset, rule = fm.stage_frame(xyz, cls)
        np.testing.assert_array_equal(keep, [False, True, True, True, False])
        self.assertEqual(offset[2], 383.5)              # lowest ground, not the noise return
        np.testing.assert_allclose(offset[:2], [12, 22])  # mean x/y of the kept rows
        self.assertEqual(rule, "lowest ground return")

    def test_height_origin_falls_back_without_ground_and_on_all_noise(self):
        xyz = np.array([[0, 0, 5], [1, 1, 3], [2, 2, -40]], dtype=np.float64)
        keep, offset, rule = fm.stage_frame(xyz, np.array([5, 1, 7]))
        np.testing.assert_array_equal(keep, [True, True, False])
        self.assertEqual((offset[2], rule), (3, "lowest non-noise return"))
        keep, _, rule = fm.stage_frame(xyz[:1], np.array([7]))
        self.assertFalse(keep.any())
        self.assertEqual(rule, "no non-noise return")

    def test_excluded_rows_are_exported_as_background(self):
        keep = np.array([False, True, True, False, True])
        ids, scores = fm.expand_to_rows(keep, np.array([1, 0, 2]), np.array([.5, 0, .7]))
        np.testing.assert_array_equal(ids, [0, 1, 0, 0, 2])
        np.testing.assert_allclose(scores, [0, .5, 0, 0, .7])
        with self.assertRaises(ValueError):
            fm.expand_to_rows(keep, np.array([1, 2]), np.array([.5, .7]))

    def test_scenes_use_the_forestformer3d_test_route_and_export_schema(self):
        self.assertEqual(fm.native_scene_name("/tmp/SOAP_031_native.laz"),
                         "test_SOAP_031_native")
        for name in ("scene_output", "native_scene_name", "validate_empty_sample_error"):
            self.assertTrue(getattr(fm, name).__code__.co_filename.endswith(
                "forestformer3d-sm120/ff3d_export.py"), name)


class ForestMambaCheckpointTests(unittest.TestCase):
    """The released checkpoint is an mmengine pickle: tensors, numpy and a
    logging HistoryBuffer (pickled through builtins.getattr). Only those
    globals may resolve; the HistoryBuffer is never instantiated."""

    def setUp(self):
        try:
            import torch
        except ImportError:
            self.skipTest("Optional torch environment is not installed")
        self.torch = torch

    def save_mmengine_like(self, path, extra=None):
        from collections import OrderedDict
        names = ("mmengine", "mmengine.logging", "mmengine.logging.history_buffer")
        saved = {n: sys.modules.get(n) for n in names}
        module = types.ModuleType(names[-1])

        class HistoryBuffer:
            def min(self):
                return 0

        HistoryBuffer.__module__ = HistoryBuffer.min.__module__ = names[-1]
        HistoryBuffer.__qualname__, HistoryBuffer.min.__qualname__ = \
            "HistoryBuffer", "HistoryBuffer.min"
        module.HistoryBuffer = HistoryBuffer
        for n in names:
            sys.modules[n] = module if n == names[-1] else types.ModuleType(n)
        try:
            state = OrderedDict(w=self.torch.arange(6.).reshape(2, 3),
                                n=self.torch.tensor(7))
            hub = {"buf": HistoryBuffer(), "stats": {"min": HistoryBuffer.min},
                   "arr": np.arange(3), "dtype": np.dtype("float32")}
            self.torch.save(dict(state_dict=state, message_hub=hub, **(extra or {})), path)
        finally:
            for n, m in saved.items():
                if m is None:
                    sys.modules.pop(n, None)
                else:
                    sys.modules[n] = m
        return state

    def test_state_dict_loads_without_importing_or_running_mmengine(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "ckpt.pth"
            state = self.save_mmengine_like(path)
            loaded = fmck.load_state_dict(path)
        self.assertEqual(list(loaded), ["w", "n"])
        for key in state:
            self.torch.testing.assert_close(loaded[key], state[key], rtol=0, atol=0)

    def test_any_other_global_is_refused(self):
        import pickle
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "ckpt.pth"
            self.save_mmengine_like(path, extra=dict(hook=print))
            with self.assertRaisesRegex(pickle.UnpicklingError, "builtins print"):
                fmck.load_state_dict(path)

    def test_legacy_pickles_are_refused_before_anything_is_unpickled(self):
        import pickle
        ran = []

        class Payload:
            def __reduce__(self):
                return (ran.append, ("executed",))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "legacy.pth"
            with open(path, "wb") as stream:     # a non-zip checkpoint whose first record runs code
                pickle.dump(Payload(), stream, protocol=2)
            with self.assertRaisesRegex(ValueError, "zip"):
                fmck.load_state_dict(path)
        self.assertEqual(ran, [])

    def test_torchscript_archives_are_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "scripted.pth"
            self.torch.jit.save(self.torch.jit.script(self.torch.nn.Linear(2, 2)), str(path))
            with self.assertRaisesRegex(ValueError, "TorchScript"):
                fmck.load_state_dict(path)

    def test_the_module_level_loader_is_restricted_too(self):
        import io
        import pickle
        with self.assertRaisesRegex(pickle.UnpicklingError, "builtins print"):
            fmck._PickleModule.load(io.BytesIO(pickle.dumps(print, protocol=2)))


if __name__ == "__main__":
    unittest.main()
