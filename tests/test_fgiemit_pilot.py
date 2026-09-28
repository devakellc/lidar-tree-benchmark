"""Point identity, background, fixed filters and bounded pilot execution."""
import csv
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import laspy
import numpy as np

REPO = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(REPO / "scripts"), str(REPO / "gpu")]
from fgiemit_sat_export import restore_native, patch_sources
from fgiemit_pilot_lib import aligned_labels, fixed_filter
from run_fgiemit_pilot import bounded, write_csv, docker_command
import run_fgiemit_pilot as pilot


def geometry():
    h = laspy.LasHeader(point_format=3, version="1.2")
    h.scales = np.array([0.0001] * 3)
    h.offsets = np.array([-30, -20, 1])
    cloud = laspy.LasData(h)
    cloud.x = np.array([1, 1, 1, 5]); cloud.y = np.array([2, 2, 2, 5])
    cloud.z = np.array([3, 3, 4, 8])
    cloud.return_number = [1, 2, 1, 1]; cloud.number_of_returns = [2, 2, 1, 1]
    cloud.add_extra_dim(laspy.ExtraBytesParams(name="source_row", type=np.uint32))
    cloud.source_row = [1, 4, 8, 9]
    return cloud


class NativeExportTests(unittest.TestCase):
    def test_sat_duplicate_xyz_labels_and_background_keep_original_rows(self):
        src = geometry()
        xyz = np.column_stack((src.x, src.y, src.z))
        local = (xyz - xyz.min(axis=0)).astype(np.float32)
        labels = restore_native(src, local, np.arange(4), [-1, 7, 2, -1])
        np.testing.assert_array_equal(labels, [0, 8, 3, 0])
        # Even equal coordinates must not hide a permutation of source identity.
        for rows in ([1, 0, 2, 3], [0, 0, 2, 3], [0, 1, 2]):
            with self.assertRaisesRegex(ValueError, "native rows"):
                restore_native(src, local, rows, [-1, 7, 2, -1])
        moved = local.copy(); moved[2, 2] += .001
        with self.assertRaisesRegex(ValueError, "coordinates"):
            restore_native(src, moved, np.arange(4), [-1, 7, 2, -1])
        for bad in ([-2, 0, 1, 2], [0, 1, np.nan, 2], [0, 1, 2], [0, .5, 2, 3]):
            with self.assertRaisesRegex(ValueError, "labels"):
                restore_native(src, local, np.arange(4), bad)

    def test_prediction_export_admits_only_exact_original_las_support(self):
        source = geometry()
        pred = laspy.LasData(source.header.copy(), source.points.copy())
        for name in ("sat_row", "pred_instance"):
            pred.add_extra_dim(laspy.ExtraBytesParams(name=name, type=np.uint32))
        pred.sat_row = np.arange(4); pred.pred_instance = [0, 8, 3, 0]
        labels, scores = aligned_labels(source, pred, "segmentanytree")
        np.testing.assert_array_equal(labels, [0, 8, 3, 0]); self.assertIsNone(scores)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out.laz"; pred.write(path)
            aligned_labels(source, laspy.read(path), "segmentanytree")
        for field, values in (("source_row", [1, 8, 4, 9]),
                              ("return_number", [1, 1, 1, 1]), ("sat_row", [0, 0, 2, 3])):
            bad = laspy.LasData(pred.header.copy(), pred.points.copy())
            setattr(bad, field, values)
            with self.assertRaises(ValueError):
                aligned_labels(source, bad, "segmentanytree")
        pred.header.scales = [.001] * 3
        with self.assertRaisesRegex(ValueError, "frame"):
            aligned_labels(source, pred, "segmentanytree")

    def test_fixed_filter_keeps_boundary_values_and_uses_same_retained_rows(self):
        labels = np.repeat([0, 7, 8, 9], [2, 39, 40, 40])
        z = np.r_[0, 30, np.linspace(0, 2, 39), np.linspace(0, 1.5, 40),
                  np.linspace(0, 1.499, 40)]
        result, confidence = fixed_filter(labels, z)
        self.assertEqual(confidence, {8: 40})
        self.assertEqual(int(sum(result > 0)), 40)
        scores = np.linspace(0, 1, len(labels))
        same, native_conf = fixed_filter(labels, z, scores)
        np.testing.assert_array_equal(result, same)
        self.assertAlmostEqual(native_conf[8], scores[labels == 8].mean())
        empty, confidence = fixed_filter(np.zeros(4), np.arange(4))
        self.assertFalse(empty.any()); self.assertEqual(confidence, {})

    def test_ff3d_requires_full_rows_zero_background_score_and_one_outer_scene(self):
        source = geometry()
        pred = laspy.LasData(source.header.copy(), source.points.copy())
        pred.add_extra_dim(laspy.ExtraBytesParams(name="ff3d_row", type=np.uint32))
        pred.add_extra_dim(laspy.ExtraBytesParams(name="ff3d_score", type=np.float32))
        pred.ff3d_row = np.arange(4)
        pred.ff3d_score = [0, .4, .5, 0]
        pred.point_source_id = [0, 7, 8, 0]
        aligned_labels(source, pred, "forestformer3d")
        for field, bad in (("ff3d_score", [.2, .4, .5, 0]),
                           ("user_data", [0, 0, 1, 0]), ("ff3d_row", [1, 0, 2, 3])):
            changed = laspy.LasData(pred.header.copy(), pred.points.copy())
            setattr(changed, field, bad)
            with self.assertRaises(ValueError):
                aligned_labels(source, changed, "forestformer3d")
        pred.points = pred.points[:-1].copy()
        with self.assertRaisesRegex(ValueError, "coverage"):
            aligned_labels(source, pred, "forestformer3d")

    def test_export_patch_refuses_unknown_or_prepatched_sources(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            dataset = home / "torch_points3d/datasets/segmentation/treeins.py"
            tracker = home / "torch_points3d/metrics/panoptic_tracker_pointgroup_treeins.py"
            dataset.parent.mkdir(parents=True); tracker.parent.mkdir(parents=True)
            dataset.write_text("# incompatible layout\n")
            tracker.write_text("# incompatible layout\n")
            with self.assertRaisesRegex(ValueError, "Unexpected pinned"):
                patch_sources(home)


class ExecutionTests(unittest.TestCase):
    def test_failed_cell_stops_expansion_without_becoming_an_empty_prediction(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            comparison = root / "development_comparison"
            comparison.mkdir()
            (comparison / "declaration.json").write_text("{}")
            (comparison / "reference_apexes.csv").write_text("plot,instance\n1001,1\n")
            (root / "development_checkpoint_provenance_v2.json").write_text(
                json.dumps(dict(gpu_root=str(root / "gpu"))))
            runtime = root / "runtime"
            runtime.mkdir(); (runtime / "runtime.json").write_text("{}")
            cells = [dict(plot=p, arm=a, reference_count=1)
                     for p in pilot.PILOT for a in pilot.ARMS]
            out = root / "attempt"
            with mock.patch.object(pilot, "preflight", return_value=cells), \
                    mock.patch.object(pilot, "verify") as verify, \
                    mock.patch.object(pilot, "run_cell", side_effect=[
                        dict(state="successful_empty", predictions=0),
                        RuntimeError("synthetic export failure")]) as execute:
                pilot.run(root, out, runtime)
            receipt = json.loads((out / "pilot.json").read_text())
            self.assertEqual(execute.call_count, 2)
            self.assertEqual([c["state"] for c in receipt["cells"]],
                             ["successful_empty", "failed"] + ["planned"] * 7)
            self.assertNotIn("predictions", receipt["cells"][1])
            self.assertIn("synthetic export failure", receipt["cells"][1]["error"])
            self.assertTrue(receipt["expansion_stopped"])
            self.assertFalse(receipt["complete_pilot"])
            self.assertFalse((out / cells[2]["plot"] / cells[2]["arm"]).exists())
            verify.assert_called_once_with(root, out, runtime)

    def test_model_mounts_cannot_expose_cell_references_or_shared_annotation_root(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "data"
            for arm in ("segmentanytree", "forestformer3d"):
                directory = root / "attempt/1001" / arm
                directory.mkdir(parents=True)
                reference = directory / "reference_apexes.csv"
                reference.write_text("sensitive reference fixture\n")
                cell = dict(arm=arm, plot="1001", config=dict(image="fixture-image"))
                with mock.patch("run_fgiemit_pilot.subprocess.run"):
                    command, _ = docker_command(cell, directory, root, Path(tmp) / "gpu")
                mounts = [command[i + 1] for i, v in enumerate(command) if v == "-v"]
                writable = [m for m in mounts if not m.endswith(":ro")]
                self.assertEqual(writable, [f"{directory / 'model_io'}:/output"])
                for mount in mounts:
                    host = Path(mount.split(":")[0])
                    self.assertNotEqual(host, reference)
                    self.assertFalse(reference.is_relative_to(host))
                    self.assertNotEqual(host, root)
                self.assertEqual(list((directory / "model_io").iterdir()), [])
                with self.assertRaises(FileExistsError), mock.patch("run_fgiemit_pilot.subprocess.run"):
                    docker_command(cell, directory, root, Path(tmp) / "gpu")

    def test_wall_limit_terminates_the_process_group(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            pidfile = directory / "pid"
            command = [sys.executable, "-c",
                "import os,time,pathlib; pathlib.Path(__import__('sys').argv[1]).write_text(str(os.getpid())); time.sleep(20)",
                str(pidfile)]
            with self.assertRaises(subprocess.TimeoutExpired):
                bounded(command, directory, timeout=.3)
            pid = int(pidfile.read_text())
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)

    def test_R_mask_and_apex_targets_remain_separate_with_background(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            cloud = laspy.LasData(laspy.LasHeader(point_format=3, version="1.2"))
            cloud.x = np.repeat([0, 10, 20], 40)
            cloud.y = np.zeros(120); cloud.z = np.tile(np.linspace(0, 5, 40), 3)
            cloud.add_extra_dim(laspy.ExtraBytesParams(name="tree_index", type=np.uint32))
            cloud.tree_index = np.repeat([1, 2, 0], 40)
            cloud.write(d / "ref.laz")
            np.savetxt(d / "labels.csv", np.repeat([7, 0, 8], 40), fmt="%d",
                       header="pred_instance", comments="")
            refs, preds = [], []
            for policy in ("max_agl", "isolated_top_agl", "historical_raw"):
                refs.extend([dict(instance=1,policy=policy,x=0,y=0,z=5,category="A"),
                             dict(instance=2,policy=policy,x=10,y=0,z=5,category="D")])
                preds.extend([dict(instance=7,policy=policy,x=0,y=0,z=5),
                              dict(instance=8,policy=policy,x=20,y=0,z=5)])
            write_csv(d / "refs.csv", refs, list(refs[0]))
            write_csv(d / "preds.csv", preds, list(preds[0]))
            command = ["Rscript", str(REPO / "scripts/fgiemit_pilot_cell.R"), "score",
                str(d / "preds.csv"), str(d / "refs.csv"), "segmentanytree",
                str(d / "labels.csv"), str(d / "ref.laz"), str(d / "score.json")]
            subprocess.run(command, cwd=REPO, check=True, capture_output=True, timeout=60)
            metrics = json.loads((d / "score.json").read_text())
            self.assertEqual(metrics["mask"][0]["TP"], 1)
            self.assertEqual(metrics["mask"][0]["FP"], 1)
            self.assertEqual(metrics["mask"][0]["FN"], 1)
            self.assertEqual(metrics["mask"][0]["tp_A"], 1)
            self.assertEqual(metrics["mask"][0]["fn_D"], 1)
            self.assertEqual([r["apex_TP"] for r in metrics["detection"]], [1, 1, 1])


if __name__ == "__main__":
    unittest.main()
