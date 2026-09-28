"""Complete-matrix execution must reuse the pilot exactly and stop on failure."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import run_fgiemit_development as development


def completed(expected, directory, empty=False):
    n = 0 if empty else 1
    detection = [dict(policy=p, apex_TP=n, apex_FP=0, apex_FN=1-n, apex_F1=float(n))
                 for p in (development.POLICIES[:1] if expected["arm"] == "chm_vwf"
                           else development.POLICIES)]
    mask = None
    if expected["arm"] != "chm_vwf":
        m = dict(TP=n, FP=0, FN=1-n, n_pred=n, n_ref=1, sum_iou=float(n), sum_maxiou=float(n))
        for category in "ABCD":
            ref = int(category == "A")
            m.update({"n_" + category: ref, "tp_" + category: ref*n, "fn_" + category: ref*(1-n)})
        mask = [m]
    metrics = dict(detection=detection, mask=mask)
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "metrics.json").write_text(json.dumps(metrics))
    (directory / "execution.json").write_text(json.dumps(dict(exit_code=0, wall_seconds=1.5)))
    return dict(state="successful_empty" if empty else "successful_nonempty", predictions=n,
                metrics=metrics, inference_wall_seconds=1.5, resources={})


def fixture(root):
    matrix = dict(cells=[dict(plot=p, arm=a, pilot=p in development.PILOT, reference_count=1)
                        for p in sorted(development.DEVELOPMENT) for a in development.ARMS])
    pilot_dir, runtime = root / "pilot", root / "runtime"
    pilot_dir.mkdir(); runtime.mkdir()
    admitted = dict(complete_pilot=True, code_sha256=development.pilot.code_hashes(), cells=[])
    lookup = {development.key(c): c for c in matrix["cells"]}
    for p in development.PILOT:
        for a in development.ARMS:
            expected = lookup[p, a]
            result = completed(expected, pilot_dir / p / a)
            admitted["cells"].append(dict(plot=p, arm=a, reference_count=1, **result))
    (pilot_dir / "pilot.json").write_text(json.dumps(admitted))
    (runtime / "runtime.json").write_text("{}")
    declaration = root / "development_comparison"
    declaration.mkdir()
    (declaration / "declaration.json").write_text("{}")
    (declaration / "matrix.json").write_text(json.dumps(matrix))
    (declaration / "reference_apexes.csv").write_text("plot,instance\n1001,1\n")
    (root / "development_checkpoint_provenance_v2.json").write_text(
        json.dumps(dict(gpu_root=str(root / "gpu"))))
    return matrix, admitted, pilot_dir, runtime


class DevelopmentExecutionTests(unittest.TestCase):
    def test_complete_run_executes_only_twenty_one_new_cells_and_seals_both_origins(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            matrix, admitted, pilot_dir, runtime = fixture(root)
            out = root / "run"
            with mock.patch.object(development, "preflight", return_value=(matrix, admitted)), \
                    mock.patch.object(development.pilot, "run_cell", side_effect=lambda c,d,*_: completed(c,d)) as run:
                self.assertTrue(development.run(root, out, pilot_dir, runtime))
                receipt = development.verify(root, out, pilot_dir, runtime)
            self.assertEqual([development.key(c.args[0]) for c in run.call_args_list],
                             [development.key(c) for c in matrix["cells"] if not c["pilot"]])
            self.assertEqual(run.call_count, 21)
            self.assertEqual(sum(c["origin"] == "pilot" for c in receipt["cells"]), 9)
            self.assertEqual(sum(c["origin"] == "new" for c in receipt["cells"]), 21)
            self.assertFalse(any((out / p).exists() for p in development.PILOT))
            self.assertEqual(receipt["execution_code_sha256"], admitted["code_sha256"])
            # Sealed output tampering must be rejected independently of record state.
            cell = next(c for c in receipt["cells"] if c["origin"] == "new")
            (root / cell["source_directory"] / "metrics.json").write_text("{}")
            with mock.patch.object(development, "preflight", return_value=(matrix, admitted)), \
                    self.assertRaisesRegex(ValueError, "accepted outputs"):
                development.verify(root, out, pilot_dir, runtime)

    def test_failure_stops_only_the_remaining_queue_and_retains_all_pilot_cells(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            matrix, admitted, pilot_dir, runtime = fixture(root)
            out = root / "run"
            count = 0
            def execute(c, d, *_):
                nonlocal count
                count += 1
                if count == 2:
                    raise RuntimeError("export fixture failure")
                return completed(c, d, empty=True)
            with mock.patch.object(development, "preflight", return_value=(matrix, admitted)), \
                    mock.patch.object(development.pilot, "run_cell", side_effect=execute):
                self.assertFalse(development.run(root, out, pilot_dir, runtime))
                receipt = development.verify(root, out, pilot_dir, runtime)
            states = [c["state"] for c in receipt["cells"] if c["origin"] == "new"]
            self.assertEqual(states, ["successful_empty", "failed"] + ["planned"] * 19)
            self.assertEqual(count, 2)
            failed = next(c for c in receipt["cells"] if c["state"] == "failed")
            self.assertNotIn("predictions", failed)
            self.assertEqual(sum(c["state"] in development.SUCCESS for c in receipt["cells"]), 10)

    def test_reuse_rejects_incomplete_pilot_and_changed_denominators(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            matrix, admitted, pilot_dir, runtime = fixture(root)
            with mock.patch.object(development.pilot, "verify"):
                development.preflight(root, pilot_dir, runtime)
                admitted["complete_pilot"] = False
                (pilot_dir / "pilot.json").write_text(json.dumps(admitted))
                with self.assertRaisesRegex(ValueError, "complete, successfully"):
                    development.preflight(root, pilot_dir, runtime)
            cell = admitted["cells"][0]
            expected = matrix["cells"][0]
            changed = dict(expected, reference_count=2)
            with self.assertRaisesRegex(ValueError, "declared support"):
                development.validate_success(cell, changed, pilot_dir / cell["plot"] / cell["arm"])

    def test_records_cannot_redirect_reused_outputs_or_advance_after_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            matrix, admitted, pilot_dir, runtime = fixture(root)
            out = root / "run"
            records = development.records_for(matrix, admitted, root, out, pilot_dir)
            receipt = dict(cells=records, complete_detector_matrix=False, expansion_stopped=False)
            development.validate_records(receipt, matrix, admitted, root, out, pilot_dir)
            for field, value in (("source_directory", "../foreign"), ("predictions", 9),
                                  ("reference_count", 9), ("origin", "new")):
                changed = copy.deepcopy(receipt)
                changed["cells"][0][field] = value
                with self.assertRaises(ValueError):
                    development.validate_records(changed, matrix, admitted, root, out, pilot_dir)
            changed = copy.deepcopy(receipt)
            pending = [c for c in changed["cells"] if c["origin"] == "new"]
            pending[0].update(state="failed", error="fixture")
            pending[1]["state"] = "successful_nonempty"
            changed["expansion_stopped"] = True
            with self.assertRaisesRegex(ValueError, "expansion after failure"):
                development.validate_records(changed, matrix, admitted, root, out, pilot_dir)


if __name__ == "__main__":
    unittest.main()
