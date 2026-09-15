"""Lossless reference bridge tests; run with the official evaluator environment."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

import laspy
import numpy as np

spec = importlib.util.spec_from_file_location(
    "fgi_reference", Path(__file__).resolve().parents[1] / "gpu/prepare_fgiemit_reference.py"
)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class ReferenceBridgeTests(unittest.TestCase):
    def test_preserves_coordinates_labels_and_background_after_many_extra_fields(self):
        header = laspy.LasHeader(point_format=7, version="1.4")
        header.scales = [0.000001] * 3
        cloud = laspy.LasData(header)
        cloud.x = [-1.234567, 0, 3.456789]
        cloud.y = [4, 5, 6]
        cloud.z = [1, 9, 18]
        cloud.classification = [0, 1, 5]
        for i in range(12):
            cloud.add_extra_dim(laspy.ExtraBytesParams(name=f"extra_{i}", type="float32"))
        cloud.add_extra_dim(laspy.ExtraBytesParams(name="tree_index", type="int32"))
        cloud.tree_index = [0, 42, 0]
        with tempfile.TemporaryDirectory() as tmp:
            source, output = Path(tmp) / "in.las", Path(tmp) / "out.laz"
            cloud.write(source)
            bridge.prepare_reference(source, output)
            result = laspy.read(output)
        self.assertEqual(list(result.point_format.extra_dimension_names), ["tree_index"])
        for field in ("X", "Y", "Z", "classification", "tree_index"):
            np.testing.assert_array_equal(result[field], cloud[field])
        np.testing.assert_array_equal(result.header.scales, cloud.header.scales)
        np.testing.assert_array_equal(result.header.offsets, cloud.header.offsets)

    def test_missing_labels_are_rejected(self):
        cloud = laspy.LasData(laspy.LasHeader(point_format=3, version="1.2"))
        cloud.x, cloud.y, cloud.z = [0], [0], [0]
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "in.las"
            cloud.write(source)
            with self.assertRaisesRegex(ValueError, "tree_index"):
                bridge.prepare_reference(source, Path(tmp) / "out.laz")


if __name__ == "__main__":
    unittest.main()
