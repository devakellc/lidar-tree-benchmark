"""Original-row, return-density and annotation isolation contracts."""
import copy
from pathlib import Path
import sys
import tempfile
import unittest

import laspy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import prepare_fgiemit_development as prep


def fixture(directory):
    header = laspy.LasHeader(point_format=7, version="1.4")
    header.scales = [0.000001] * 3
    for name in ("tree_index", "edge", "dead"):
        header.add_extra_dim(laspy.ExtraBytesParams(name=name, type="uint32"))
    cloud = laspy.LasData(header)
    cloud.x = [0, 2, 2, 0, 1, 1, 1, 1, 1, 1, 1, 1, 20]
    cloud.y = [0, 0, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 20]
    cloud.z = [0, 0, 0, 0, 3, 3, 4, 5, 0, 0, 0, 0, 8]
    cloud.classification = [0, 0, 2, 3, 1, 1, 1, 1, 0, 0, 4, 0, 5]
    cloud.tree_index = [0, 0, 0, 0, 1, 1, 2, 2, 0, 0, 0, 0, 0]
    cloud.return_number = [1, 1, 1, 1, 2, 2, 1, 1, 1, 1, 1, 1, 1]
    cloud.number_of_returns = [1, 1, 1, 1, 2, 2, 1, 1, 1, 1, 1, 1, 1]
    cloud.edge = [0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0]
    cloud.dead = [0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0]
    path = directory / "source.las"
    cloud.write(path)
    metadata = dict(area=0.126, n_trees=dict(A=1, B=0, C=0, D=1, all=2),
                    trees={1: dict(x=1, y=1, h=3, c="D"), 2: dict(x=1, y=1, h=5, c="A")})
    return laspy.read(path), metadata


class DevelopmentInputsTests(unittest.TestCase):
    def test_reserve_test_and_duplicate_ids_rejected_before_open(self):
        for plots in ("1003", "1002", "1001,1001", "1001,1010", ""):
            with self.assertRaisesRegex(ValueError, "development plots"):
                prep.select_plots(plots)
        self.assertEqual(len(prep.select_plots(None)), 10)

    def test_real_returns_and_retained_footprint_drive_density(self):
        with tempfile.TemporaryDirectory() as tmp:
            cloud, metadata = fixture(Path(tmp))
            keep, rows, info = prep.validate_points(cloud, metadata)
            self.assertEqual(info["footprint_area_m2"], 4)
            self.assertEqual(info["retained_points"], 12)
            self.assertEqual(info["first_returns"], 10)
            self.assertEqual(info["pdens"], 3)
            self.assertEqual(info["frdens"], 2.5)
            self.assertFalse(keep[-1])
            self.assertTrue(np.array_equal(rows, np.arange(12)))
            self.assertFalse(info["independent_AGL_validated"])

    def test_reference_and_geometry_roundtrip_preserve_duplicate_rows_and_returns(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            cloud, metadata = fixture(directory)
            keep, rows, _ = prep.validate_points(cloud, metadata)
            prep.export_inputs(cloud, keep, rows, directory)
            model = laspy.read(directory / "geometry.las")
            ref = laspy.read(directory / "reference.laz")
            self.assertEqual(list(model.point_format.extra_dimension_names), ["source_row"])
            self.assertTrue(np.all(model.classification == 1))
            self.assertTrue(np.all(model.red == 0))
            self.assertEqual(model.X[4], model.X[5])
            self.assertNotEqual(model.source_row[4], model.source_row[5])
            self.assertEqual(ref.edge[4], 1)
            self.assertEqual(ref.dead[6], 1)
            self.assertEqual(set(np.unique(ref.classification)), {0, 1, 2, 3, 4})
            model.return_number = np.ones(len(rows), dtype="uint8")
            with self.assertRaisesRegex(ValueError, "return_number"):
                prep.verify_geometry(cloud, model, rows)

    def test_annotation_and_return_inconsistencies_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            cloud, metadata = fixture(Path(tmp))
            changed = copy.deepcopy(metadata)
            del changed["trees"][2]
            with self.assertRaisesRegex(ValueError, "instance IDs disagree"):
                prep.validate_points(cloud, changed)
            cloud.tree_index[0] = 1
            with self.assertRaisesRegex(ValueError, "Semantic trees"):
                prep.validate_points(cloud, metadata)
            cloud.tree_index[0] = 0
            cloud.return_number[0] = 0
            with self.assertRaisesRegex(ValueError, "return numbers"):
                prep.validate_points(cloud, metadata)

    def test_normalization_requires_complete_exact_identity_and_keeps_negative_heights(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            cloud, metadata = fixture(directory)
            keep, rows, _ = prep.validate_points(cloud, metadata)
            prep.export_inputs(cloud, keep, rows, directory)
            raw = laspy.read(directory / "geometry.las")
            normalized = laspy.read(directory / "geometry.las")
            normalized.classification[:4] = 2
            normalized.z[8] = -0.6
            stats, heights = prep.normalization_diagnostics(raw, normalized,
                                                          cloud.tree_index[keep], metadata)
            self.assertEqual(stats["below_minus_05_fraction"], 1 / 12)
            self.assertEqual(stats["outside_ground_hull_fraction"], 0)
            self.assertEqual([h["difference_m"] for h in heights], [0, 0])
            normalized.source_row[5] = 4
            with self.assertRaisesRegex(ValueError, "source_row"):
                prep.normalization_diagnostics(raw, normalized, cloud.tree_index[keep], metadata)


if __name__ == "__main__":
    unittest.main()
