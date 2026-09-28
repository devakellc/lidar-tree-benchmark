"""Reserve admission, immutable attempts, support and contract replay."""
import copy
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import laspy
import numpy as np
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import prepare_fgiemit_reserve as reserve
from test_fgiemit_policy import fixture as policy_fixture


def fixture(root):
    args = policy_fixture()
    (root / "source/training").mkdir(parents=True)
    metadata = {}
    for inventory, count in zip(args[5], reserve.policy.RESERVE_COUNTS):
        plot = inventory["plot"]
        header = laspy.LasHeader(point_format=7, version="1.4")
        for name in ("tree_index", "edge", "dead"):
            header.add_extra_dim(laspy.ExtraBytesParams(name=name, type="uint32"))
        cloud = laspy.LasData(header)
        cloud.x = [0, 2, 2, 0] + [1] * (2 * count) + [20]
        cloud.y = [0, 0, 2, 2] + [1] * (2 * count) + [20]
        cloud.z = [0] * 4 + [3, 5] * count + [30]
        cloud.classification = [0, 2, 3, 4] + [1] * (2 * count) + [5]
        cloud.tree_index = [0] * 4 + np.repeat(np.arange(1, count + 1), 2).tolist() + [0]
        cloud.return_number = [1] * 4 + [1, 2] * count + [1]
        cloud.number_of_returns = [1] * 4 + [2] * (2 * count) + [1]
        cloud.edge = np.ones(len(cloud.points), dtype="uint32")
        cloud.dead = np.ones(len(cloud.points), dtype="uint32")
        path = root / f"source/training/plot_{plot}.las"
        cloud.write(path)
        inventory["header_points"] = str(len(cloud.points))
        args[0]["source_sha256"][str(path.relative_to(root))] = reserve.file_hash(path)
        metadata[int(plot)] = dict(area=.126, n_trees=dict(A=count, B=0, C=0, D=0, all=count),
            trees={i: dict(x=1, y=1, h=5, c="A") for i in range(1, count + 1)})
    (root / "source/plot_data.yaml").write_text(yaml.safe_dump(metadata))
    frozen, plan = reserve.policy.build_policy(*args)
    return dict(policy=frozen, plan=plan, declaration=args[0], parent_sha256={"freeze.json": "a" * 64},
        runtime_directory="/fixture/runtime", runtime_sha256="b" * 64,
        execution_code_sha256={"engine.py": "c" * 64},
        normalization=dict(method="synthetic geometry fixture", threads=1, lidR="fixture", RCSF="fixture",
                           rows=0, ground_points=0, independently_validated_AGL=False))


class ReserveInputsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "development"
        self.out = Path(self.tmp.name) / "reserve"
        self.context = fixture(self.root)
        patcher = mock.patch.object(reserve, "preflight", return_value=self.context)
        patcher.start()
        self.addCleanup(patcher.stop)

    def normalize(self, command, **kwargs):
        self.assertEqual(kwargs["timeout"], 600)
        cloud = laspy.read(command[2])
        cloud.classification[:4] = 2
        cloud.write(command[3])
        reserve.write_json(Path(command[4]), dict(self.context["normalization"],
                                                 rows=len(cloud.points), ground_points=4))

    def prepare(self):
        with mock.patch.object(reserve.subprocess, "run", side_effect=self.normalize) as run:
            self.assertTrue(reserve.prepare(self.root, self.out))
            self.assertEqual(run.call_count, 3)

    def rehash(self):
        manifest = reserve.read_json(self.out / "manifest.json")
        manifest["output_sha256"] = reserve.output_hashes(self.out)
        reserve.write_json(self.out / "manifest.json", manifest)

    def test_scope_location_and_source_digest_fail_before_point_read(self):
        for out in (self.root, self.root / "reserve", self.root.parent):
            with self.subTest(out=out), self.assertRaisesRegex(ValueError, "outside"):
                reserve.check_location(self.root, out)
        for plot in ("1001", "1002", "../1003"):
            with self.subTest(plot=plot), self.assertRaisesRegex(ValueError, "original reserve"):
                reserve.source_for(self.root, self.context, plot)
        source = self.root / "source/training/plot_1003.las"
        source.write_bytes(source.read_bytes() + b"changed")
        with self.assertRaisesRegex(ValueError, "source changed"):
            reserve.source_for(self.root, self.context, "1003")

    def test_complete_inputs_replay_and_freeze_exact_support_and_policy(self):
        self.prepare()
        self.assertTrue(reserve.verify(self.root, self.out))
        contract = reserve.read_json(self.out / "contract/matrix.json")
        self.assertEqual(len(contract["cells"]), 9)
        self.assertEqual(contract["reference_count"], 257)
        self.assertEqual(contract["planned_primary_scoring_cells"], 15)
        self.assertEqual(contract["inference"], self.context["policy"]["inference"])
        self.assertFalse(contract["execution_enabled"])
        self.assertFalse(contract["runner_validated"])
        self.assertEqual(len(reserve.policy.calibration.read_csv(
            self.out / "contract/reference_apexes.csv")), 771)
        for cell in contract["cells"]:
            self.assertNotIn("fold", cell)
            self.assertNotIn("probability", cell)
            self.assertLess(cell["frdens"], cell["pdens"])
            self.assertTrue(cell["input"].startswith("inputs/" + cell["plot"] + "/"))
            if cell["arm"] != "chm_vwf":
                self.assertEqual(cell["config"], self.context["policy"]["instance_configurations"][cell["arm"]])
        with self.assertRaisesRegex(ValueError, "fresh reserve directory"):
            reserve.prepare(self.root, self.out)

    def test_failed_normalization_preserves_all_receipts_without_contract_or_retry(self):
        def fail_middle(command, **kwargs):
            if Path(command[2]).parent.name == "1010":
                raise subprocess.TimeoutExpired(command, 600)
            self.normalize(command, **kwargs)
        with mock.patch.object(reserve.subprocess, "run", side_effect=fail_middle) as run:
            self.assertFalse(reserve.prepare(self.root, self.out))
            self.assertEqual(run.call_count, 3)
        self.assertFalse(reserve.verify(self.root, self.out))
        self.assertFalse((self.out / "contract").exists())
        receipt = reserve.read_json(self.out / "inputs/1010/receipt.json")
        self.assertIn("TimeoutExpired", receipt["error"])
        manifest = reserve.read_json(self.out / "manifest.json")
        with self.assertRaisesRegex(ValueError, "Every original reserve"):
            reserve.build_contract(self.context, manifest["results"], manifest["output_sha256"])

    def test_model_annotations_row_identity_and_return_changes_are_rejected(self):
        self.prepare()
        directory = self.out / "inputs/1003"
        original = (directory / "geometry.las").read_bytes()
        for field, value, message in (("intensity", 1, "unused source field"),
                                      ("source_row", 100, "source row identity"),
                                      ("return_number", 2, "return_number")):
            with self.subTest(field=field):
                (directory / "geometry.las").write_bytes(original)
                cloud = laspy.read(directory / "geometry.las")
                cloud[field][0] = value
                cloud.write(directory / "geometry.las")
                self.rehash()
                with self.assertRaisesRegex(ValueError, message):
                    reserve.verify(self.root, self.out)

    def test_missing_reordered_and_changed_support_fail_contract_admission(self):
        self.prepare()
        manifest = reserve.read_json(self.out / "manifest.json")
        for kind in ("missing", "reordered", "reference", "density", "frame"):
            rows = copy.deepcopy(manifest["results"])
            if kind == "missing": rows.pop()
            elif kind == "reordered": rows.reverse()
            elif kind == "reference": rows[0]["reference_trees"] -= 1
            elif kind == "density": rows[0]["frdens"] = rows[0]["pdens"]
            else: rows[0]["coordinate_frame"] = "EPSG:3857"
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                reserve.build_contract(self.context, rows, manifest["output_sha256"])

    def test_rehashed_contract_tuning_is_still_rejected(self):
        self.prepare()
        path = self.out / "contract/matrix.json"
        contract = reserve.read_json(path)
        contract["cells"][1]["config"]["additional_score_cutoff"] = .5
        reserve.write_json(path, contract)
        self.rehash()
        with self.assertRaisesRegex(ValueError, "execution contract"):
            reserve.verify(self.root, self.out)

    def test_parent_changes_and_symlinked_artifacts_fail_replay(self):
        self.prepare()
        self.context["parent_sha256"]["freeze.json"] = "changed"
        with self.assertRaisesRegex(ValueError, "parents"):
            reserve.verify(self.root, self.out)
        (self.out / "alias").symlink_to(self.out / "summary.csv")
        with self.assertRaisesRegex(ValueError, "symlinks"):
            reserve.output_hashes(self.out)


if __name__ == "__main__":
    unittest.main()
