"""Whole-plot declaration, complete-parent admission and calibration sealing."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import calibrate_fgiemit_development as calibration
from test_fgiemit_development_summary import summary_fixture


def fixture(root):
    run, run_dir, pilot_dir, runtime = summary_fixture(root)
    matrix = calibration.development.read_json(root / "development_comparison/matrix.json")
    matrix["calibration_cells"] = []
    for p in sorted(calibration.development.DEVELOPMENT):
        for arm in calibration.development.ARMS:
            targets = ["apex_max_agl"] if arm == "chm_vwf" else ["apex_max_agl", "mask_iou_0.5"]
            for target in targets:
                matrix["calibration_cells"].append(dict(fold=f"leave_{p}_out", validation_plot=p,
                    calibration_plots=sorted(calibration.development.DEVELOPMENT - {p}), arm=arm,
                    target=target, confidence_feature=calibration.FEATURES[arm], state="planned"))
    (root / "development_comparison/matrix.json").write_text(json.dumps(matrix))
    summary_dir = root / "summary"
    summary_dir.mkdir()
    (summary_dir / "summary.json").write_text("{}")
    return matrix, (root, run_dir, pilot_dir, runtime, summary_dir, root / "calibration")


def fake_compute(*args, **kwargs):
    out = Path(args[0][-1])
    folds = calibration.read_csv(out / "folds.csv")
    status = [dict(f, n_pred=1, TP=1, state="successful_nonempty", fit_state="unavailable",
                   calibrated=0, unavailable=1) for f in folds]
    calibration.summary.write_csv(out / "status.csv", status)
    analysis = dict(cells=50, fitted_cells=0, unavailable_fit_cells=50,
        validation_predictions=50, calibrated_predictions=0, resamples=1000, seed=20260923,
        refit_in_bootstrap=False, reserve_evaluation_enabled=False)
    (out / "analysis.json").write_text(json.dumps(analysis))
    for name in calibration.OUTPUTS:
        if not (out / name).exists():
            (out / name).write_text("fixture output\n")


class CalibrationTests(unittest.TestCase):
    def test_exact_declared_folds_reject_overlap_reserve_target_and_feature_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            matrix, _ = fixture(Path(tmp))
            self.assertEqual(len(calibration.fold_rows(matrix)), 50)
            for key, value in (("calibration_plots", ["1001"] * 9), ("validation_plot", "1003"),
                               ("target", "apex_historical_raw"), ("confidence_feature", "normalized")):
                changed = copy.deepcopy(matrix)
                changed["calibration_cells"][0][key] = value
                with self.assertRaisesRegex(ValueError, "exact fifty"):
                    calibration.fold_rows(changed)
            matrix["calibration_cells"].pop()
            with self.assertRaisesRegex(ValueError, "exact fifty"):
                calibration.fold_rows(matrix)

    def test_incomplete_parent_never_creates_outputs_or_invokes_r(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, paths = fixture(Path(tmp))
            with mock.patch.object(calibration.summary, "verify", return_value={"primary_comparison_enabled": False}), \
                    mock.patch.object(calibration.subprocess, "run") as compute, \
                    self.assertRaisesRegex(ValueError, "complete detector"):
                calibration.calibrate(*paths)
            compute.assert_not_called()
            self.assertFalse(paths[-1].exists())

    def test_unavailable_fits_still_seal_complete_status_and_reject_tampering(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, paths = fixture(Path(tmp))
            with mock.patch.object(calibration.summary, "verify", return_value={"primary_comparison_enabled": True}), \
                    mock.patch.object(calibration.subprocess, "run", side_effect=fake_compute):
                result = calibration.calibrate(*paths)
                calibration.verify(*paths)
                self.assertFalse(result["calibration_fitted"])
                self.assertTrue(result["complete_calibration_matrix"])
                self.assertFalse(result["reserve_evaluation_enabled"])
                with self.assertRaisesRegex(ValueError, "new immediate"):
                    calibration.calibrate(*paths)
                with mock.patch.object(calibration, "code_hashes", return_value={}), \
                        self.assertRaisesRegex(ValueError, "parent, code or outputs"):
                    calibration.verify(*paths)
                (paths[-1] / "knots.csv").write_text("tampered\n")
                with self.assertRaisesRegex(ValueError, "parent, code or outputs"):
                    calibration.verify(*paths)

    def test_status_cannot_change_denominators_and_failures_never_receive_success_receipts(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, paths = fixture(Path(tmp))
            with mock.patch.object(calibration.summary, "verify", return_value={"primary_comparison_enabled": True}), \
                    mock.patch.object(calibration.subprocess, "run", side_effect=fake_compute):
                calibration.calibrate(*paths)
                status = calibration.read_csv(paths[-1] / "status.csv")
                status[0]["calibrated"] = 2
                calibration.summary.write_csv(paths[-1] / "status.csv", status)
                with self.assertRaisesRegex(ValueError, "coverage or baseline"):
                    calibration.verify(*paths)
        with tempfile.TemporaryDirectory() as tmp:
            _, paths = fixture(Path(tmp))
            with mock.patch.object(calibration.summary, "verify", return_value={"primary_comparison_enabled": True}), \
                    mock.patch.object(calibration.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "Rscript")), \
                    self.assertRaises(subprocess.CalledProcessError):
                calibration.calibrate(*paths)
            self.assertFalse((paths[-1] / "calibration.json").exists())
            self.assertTrue((paths[-1] / "analysis.log").exists())


if __name__ == "__main__":
    unittest.main()
