"""Summary admission, missing-cell denominators and sealed analysis provenance."""
import copy
import csv
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import summarize_fgiemit_development as summary
from test_fgiemit_development_execution import fixture, completed


def summary_fixture(root):
    matrix, admitted, pilot_dir, runtime = fixture(root)
    run_dir = root / "run"
    run_dir.mkdir()
    cells = summary.development.records_for(matrix, admitted, root, run_dir, pilot_dir)
    for cell, expected in zip(cells, matrix["cells"]):
        cell.update(completed(expected, root / cell["source_directory"]))
        for mask in cell["metrics"]["mask"] or []:
            for category in "ABCD":
                for prefix in ("sumiou_", "sumcov_"):
                    mask[prefix + category] = float(category == "A")
    receipt = dict(cells=cells, complete_detector_matrix=True)
    (run_dir / "run.json").write_text(json.dumps(receipt))
    return receipt, run_dir, pilot_dir, runtime


class DevelopmentSummaryTests(unittest.TestCase):
    def test_incomplete_support_has_explicit_status_and_never_invokes_pooling(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            receipt, run_dir, pilot_dir, runtime = summary_fixture(root)
            failed = receipt["cells"][3]
            failed.update(state="failed", error="native export failed", reference_count=77)
            for field in ("metrics", "predictions", "resources", "inference_wall_seconds"):
                failed.pop(field, None)
            receipt["cells"][4] = dict(receipt["cells"][4], state="planned")
            receipt["complete_detector_matrix"] = False
            out = root / "summary"
            with mock.patch.object(summary.development, "verify", return_value=receipt), \
                    mock.patch.object(summary.subprocess, "run") as compute:
                result = summary.summarize(root, run_dir, pilot_dir, runtime, out)
                summary.verify(root, run_dir, pilot_dir, runtime, out)
            compute.assert_not_called()
            self.assertFalse(result["primary_comparison_enabled"])
            self.assertEqual(result["completed_cells"], 28)
            self.assertEqual(result["unavailable_cells"][0]["reference_count"], 77)
            self.assertEqual(set(result["output_sha256"]), {"status.csv"})
            with (out / "status.csv").open() as stream:
                status = list(csv.DictReader(stream))
            self.assertEqual(status[3]["predictions"], "")
            self.assertEqual(status[4]["predictions"], "")
            with self.assertRaisesRegex(ValueError, "complete detector"):
                summary.metric_rows(receipt)

    def test_flattening_preserves_counts_and_separates_masks_and_height_profiles(self):
        with tempfile.TemporaryDirectory() as tmp:
            receipt, *_ = summary_fixture(Path(tmp))
            rows = summary.metric_rows(receipt)
            self.assertEqual(len(rows), 90)
            self.assertEqual(sum(r["target"] == "mask_iou_0.5" for r in rows), 20)
            self.assertEqual(sum(r["target"] == "apex_max_agl" for r in rows), 30)
            self.assertTrue(all(r["sum_iou"] is None for r in rows if r["target"].startswith("apex")))
            # The rounded per-cell rate is deliberately wrong: only counts may be exported.
            receipt["cells"][0]["metrics"]["detection"][0]["apex_F1"] = .1234
            self.assertEqual(summary.metric_rows(receipt), rows)
            broken = copy.deepcopy(receipt)
            broken["cells"][0]["state"] = "failed"
            with self.assertRaisesRegex(ValueError, "Unsuccessful"):
                summary.metric_rows(broken)

    def test_complete_outputs_and_analysis_code_are_sealed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            receipt, run_dir, pilot_dir, runtime = summary_fixture(root)
            out = root / "summary"
            def compute(*_, **__):
                for name in summary.PRIMARY_FILES:
                    if not (out / name).exists():
                        (out / name).write_text("fixture output\n")
            with mock.patch.object(summary.development, "verify", return_value=receipt), \
                    mock.patch.object(summary.subprocess, "run", side_effect=compute):
                result = summary.summarize(root, run_dir, pilot_dir, runtime, out)
                summary.verify(root, run_dir, pilot_dir, runtime, out)
                self.assertEqual(result["resamples"], 1000)
                self.assertEqual(result["seed"], 20260923)
                with self.assertRaisesRegex(ValueError, "new immediate"):
                    summary.summarize(root, run_dir, pilot_dir, runtime, out)
                with mock.patch.object(summary, "code_hashes", return_value={}), \
                        self.assertRaisesRegex(ValueError, "parent, code or outputs"):
                    summary.verify(root, run_dir, pilot_dir, runtime, out)
                (out / "pooled.csv").write_text("altered\n")
                with self.assertRaisesRegex(ValueError, "parent, code or outputs"):
                    summary.verify(root, run_dir, pilot_dir, runtime, out)

    def test_failed_r_analysis_cannot_receive_a_success_receipt(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            receipt, run_dir, pilot_dir, runtime = summary_fixture(root)
            out = root / "summary"
            with mock.patch.object(summary.development, "verify", return_value=receipt), \
                    mock.patch.object(summary.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "Rscript")), \
                    self.assertRaises(subprocess.CalledProcessError):
                summary.summarize(root, run_dir, pilot_dir, runtime, out)
            self.assertFalse((out / "summary.json").exists())


if __name__ == "__main__":
    unittest.main()
