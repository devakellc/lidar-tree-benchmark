"""Regressions for the opt-in grouping-radius override of SegmentAnyTree's
compatibility shims (gpu/sat_compat/usercustomize.py).

The shim module patches the interpreter when it is imported, so the test
compiles only _patch_region_grow_radius from its source and runs it against a
stand-in torch_points_kernels module; no GPU stack is needed.

From the repository root:

    python3 -m unittest discover -s tests -p 'test_sat_compat.py'
"""
import ast
import contextlib
import io
import os
import sys
import types
import unittest
from pathlib import Path

SHIM = Path(__file__).resolve().parents[1] / "gpu" / "sat_compat" / "usercustomize.py"


def load_patch():
    """Return _patch_region_grow_radius compiled from the shim's source."""
    tree = ast.parse(SHIM.read_text(encoding="utf-8"))
    fn = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "_patch_region_grow_radius"]
    if len(fn) != 1:
        raise AssertionError("_patch_region_grow_radius not found once in the shim")
    namespace = {}
    exec(compile(ast.Module(body=fn, type_ignores=[]), str(SHIM), "exec"), namespace)
    return namespace["_patch_region_grow_radius"]


class RegionGrowRadius(unittest.TestCase):
    def setUp(self):
        self.calls = []
        fake = types.ModuleType("torch_points_kernels")

        def region_grow(pos, labels, batch, ignore_labels=[], nsample=16, radius=0.02,
                        min_cluster_size=32):
            self.calls.append((radius, nsample, min_cluster_size))
            return []

        fake.region_grow = region_grow
        self.fake, self.original = fake, region_grow
        self.saved_module = sys.modules.get("torch_points_kernels")
        sys.modules["torch_points_kernels"] = fake
        self.saved_env = os.environ.pop("SAT_CLUSTER_RADIUS", None)
        self.patch = load_patch()

    def tearDown(self):
        if self.saved_module is None:
            sys.modules.pop("torch_points_kernels", None)
        else:
            sys.modules["torch_points_kernels"] = self.saved_module
        os.environ.pop("SAT_CLUSTER_RADIUS", None)
        if self.saved_env is not None:
            os.environ["SAT_CLUSTER_RADIUS"] = self.saved_env

    def call_both_forms(self):
        """Call region_grow as the model does (keywords) and positionally."""
        self.fake.region_grow("pos", "labels", "batch", ignore_labels=[0], radius=0.3, nsample=200,
                              min_cluster_size=10)
        self.fake.region_grow("pos", "labels", "batch", [0], 200, 0.3, 10)

    def test_unset_leaves_region_grow_unchanged(self):
        self.patch()
        self.assertIs(self.fake.region_grow, self.original)
        self.call_both_forms()
        self.assertEqual(self.calls, [(0.3, 200, 10), (0.3, 200, 10)])

    def test_empty_value_leaves_region_grow_unchanged(self):
        os.environ["SAT_CLUSTER_RADIUS"] = ""
        self.patch()
        self.assertIs(self.fake.region_grow, self.original)

    def test_radius_replaces_keyword_and_positional_radius_only(self):
        os.environ["SAT_CLUSTER_RADIUS"] = "1.0181"
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.patch()
            self.call_both_forms()
        self.assertEqual(self.calls, [(1.0181, 200, 10), (1.0181, 200, 10)])
        self.assertEqual(err.getvalue(), "sat_compat: region_grow radius 1.0181 m\n")

    def test_patching_twice_wraps_once(self):
        os.environ["SAT_CLUSTER_RADIUS"] = "2.0"
        self.patch()
        wrapped = self.fake.region_grow
        self.patch()
        self.assertIs(self.fake.region_grow, wrapped)
        with contextlib.redirect_stderr(io.StringIO()):
            self.call_both_forms()
        self.assertEqual([c[0] for c in self.calls], [2.0, 2.0])

    def test_non_positive_or_malformed_radius_is_an_error(self):
        for value in ("0", "-1", "abc"):
            with self.subTest(value=value):
                os.environ["SAT_CLUSTER_RADIUS"] = value
                with self.assertRaises(ValueError):
                    self.patch()
                self.assertIs(self.fake.region_grow, self.original)


if __name__ == "__main__":
    unittest.main()
