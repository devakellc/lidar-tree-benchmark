"""Reference-height symmetry, legacy matching and declared population guards."""
import copy
import csv
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import fgiemit_comparison_lib as contract
import declare_fgiemit_comparison as declaration


def matrix_fixture():
    plots = sorted(contract.DEVELOPMENT)
    prepared = dict(plots=plots, complete_population=True, inference_run=False,
                    calibration_fitted=False, results=[], output_sha256={})
    for plot in plots:
        prepared["results"].append(dict(plot=plot, status="validated_structure",
            coordinate_frame=f"FGI-EMIT/19351234/plot_{plot}", frdens=1000, pdens=1500,
            reference_trees=3, retained_points=40))
        for file in ("geometry.las", "normalized.laz"):
            prepared["output_sha256"][f"{plot}/{file}"] = "fixture_hash"
    provenance = dict(checkpoint_identity_verified=True, inference_run=False, images={})
    for arm in ("segmentanytree", "forestformer3d"):
        provenance[arm] = dict(sha256="fixture_checkpoint")
        provenance["images"][arm] = "fixture_image"
    folds = [dict(fold=f"leave_{p}_out", validation_plot=p,
                  calibration_plots=[q for q in plots if q != p]) for p in plots]
    return prepared, provenance, folds


class ReferenceHeightTests(unittest.TestCase):
    def test_gap_boundary_ties_singletons_and_background_preserve_source_identity(self):
        raw = np.array([[0, 0, 10.25], [1, 0, 10], [2, 0, 8], [3, 0, 8],
                        [4, 0, 4], [5, 0, 99]], dtype=float)
        labels = np.array([1, 1, 2, 2, 3, 0])
        rows = np.array([10, 11, 8, 7, 22, 99])
        out = contract.apex_profiles(raw, raw.copy(), labels, rows)
        indexed = {(r["instance"], r["policy"]): r for r in out}
        self.assertEqual(len(out), 9)
        self.assertFalse(indexed[(1, "isolated_top_agl")]["trimmed"])
        self.assertEqual(indexed[(2, "max_agl")]["source_row"], 7)
        self.assertEqual(indexed[(3, "isolated_top_agl")]["source_row"], 22)
        raw[0, 2] += 0.000001
        result = contract.apex_profiles(raw, raw.copy(), labels, rows)
        trimmed = next(r for r in result if r["instance"] == 1 and r["policy"] == "isolated_top_agl")
        self.assertEqual((trimmed["source_row"], trimmed["x"], trimmed["z"]), (11, 1, 10))
        self.assertTrue(trimmed["trimmed"])

    def test_same_reducer_accepts_predictions_and_keeps_raw_and_AGL_separate(self):
        raw = np.array([[1, 1, 25], [2, 2, 24]], dtype=float)
        agl = np.array([[1, 1, 10], [2, 2, 20]], dtype=float)
        out = contract.apex_profiles(raw, agl, np.array([4, 4]), np.array([1, 2]))
        self.assertEqual([r["source_row"] for r in out], [2, 1, 1])
        self.assertEqual([r["z"] for r in out], [20, 10, 25])
        self.assertEqual(contract.apex_profiles(raw, agl, np.zeros(2), np.array([1, 2])), [])
        with self.assertRaisesRegex(ValueError, "unique"):
            contract.apex_profiles(raw, agl, np.ones(2), np.array([1, 1]))
        agl[0, 0] += 1
        with self.assertRaisesRegex(ValueError, "aligned"):
            contract.apex_profiles(raw, agl, np.ones(2), np.array([1, 2]))

    def test_existing_FGI_matcher_exposes_diagnostic_change_without_replacing_default(self):
        raw = np.array([[0, 0, 10], [6, 0, 20]], dtype=float)
        refs = contract.apex_profiles(raw, raw, np.ones(2), np.array([0, 1]))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "refs.csv"
            with path.open("w", newline="") as stream:
                writer = csv.DictWriter(stream, fieldnames=list(refs[0]))
                writer.writeheader(); writer.writerows(refs)
            repo = Path(__file__).resolve().parents[1]
            code = '''source("scripts/model_bench_lib.R")
source("scripts/transfer_audit_lib.R")
r <- read.csv(commandArgs(TRUE)[1])
p <- data.frame(x=0,y=0,z=10)
s <- vapply(c("max_agl","isolated_top_agl","historical_raw"),
 function(k) audit_apex_match(p, r[r$policy == k, ])$apex_TP, numeric(1))
legacy <- instance_apex(data.frame(X=c(0,6),Y=0,Z=c(10,20),crown_id=1))
stopifnot(identical(as.numeric(legacy[1,c("x","y","z")]), c(6,0,20)))
cat(jsonlite::toJSON(as.list(s),auto_unbox=TRUE))'''
            result = json.loads(subprocess.check_output(["Rscript", "-e", code, str(path)],
                                                        cwd=repo, text=True, timeout=60))
            self.assertEqual(result, dict(max_agl=0, isolated_top_agl=1, historical_raw=0))


class MatrixTests(unittest.TestCase):
    def test_exact_matrix_and_independent_targets_keep_reserve_closed(self):
        matrix = contract.build_matrix(*matrix_fixture())
        self.assertEqual(len(matrix["cells"]), 30)
        self.assertEqual(len(matrix["calibration_cells"]), 50)
        self.assertEqual(sum(c["mask_track"] for c in matrix["cells"]), 20)
        self.assertEqual(sum(c["pilot"] for c in matrix["cells"]), 9)
        self.assertFalse(matrix["execution_enabled"])
        self.assertFalse(matrix["reserve_evaluation_enabled"])
        for cell in matrix["calibration_cells"]:
            self.assertNotIn(cell["validation_plot"], cell["calibration_plots"])
            self.assertEqual(len(cell["calibration_plots"]), 9)
        self.assertFalse(matrix["calibration"]["threshold_search"])

    def test_incomplete_failed_cross_frame_or_leaking_folds_are_rejected(self):
        prepared, provenance, folds = matrix_fixture()
        for field, value in (("complete_population", False), ("inference_run", True)):
            changed = copy.deepcopy(prepared); changed[field] = value
            with self.assertRaises(ValueError):
                contract.build_matrix(changed, provenance, folds)
        changed = copy.deepcopy(prepared); changed["results"][0]["status"] = "failed"
        with self.assertRaisesRegex(ValueError, "pass validation"):
            contract.build_matrix(changed, provenance, folds)
        changed = copy.deepcopy(prepared); changed["results"][0]["coordinate_frame"] = "EPSG:32635"
        with self.assertRaisesRegex(ValueError, "frames"):
            contract.build_matrix(changed, provenance, folds)
        folds[0]["calibration_plots"][0] = "1003"
        with self.assertRaisesRegex(ValueError, "other nine"):
            contract.build_matrix(prepared, provenance, folds)
        with self.assertRaisesRegex(ValueError, "restricted"):
            declaration.reference_rows(Path("missing"), "1003", {})

    def test_density_parameters_have_explicit_boundaries_and_no_upsampling(self):
        for density, res, smooth in ((8, .25, 0), (7.99, .5, 3), (4, .5, 3), (1, 1, 3)):
            p = contract.chm_parameters(density, density * 2)
            self.assertEqual((p["resolution_m"], p["mean_smoothing_cells"]), (res, smooth))
        for frdens, pdens in ((.9, 2), (2, 1), (float("nan"), 4)):
            with self.assertRaises(ValueError):
                contract.chm_parameters(frdens, pdens)


class ReceiptTests(unittest.TestCase):
    def test_replay_rejects_modified_references_parents_and_reserve_release(self):
        plan = contract.build_matrix(*matrix_fixture())
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            out = root / "comparison"
            out.mkdir()
            parent = root / "parent.json"
            parent.write_text('{"frozen": true}\n')
            refs = out / "reference_apexes.csv"
            refs.write_text("instance,z\n1,12\n")
            (out / "matrix.json").write_text(json.dumps(plan))
            receipt = dict(schema_version=1, output_directory=out.name,
                inference_run=False, calibration_fitted=False,
                reserve_evaluation_enabled=False, code_sha256={}, R_environment={},
                parent_sha256={parent.name: declaration.audit.file_hash(parent)},
                protected_sha256={}, output_sha256={
                    p.name: declaration.audit.file_hash(p) for p in out.iterdir()})
            receipt_path = out / "declaration.json"
            receipt_path.write_text(json.dumps(receipt))
            with mock.patch.object(declaration, "preflight", return_value=({}, plan)), \
                 mock.patch.object(declaration, "code_hashes", return_value={}), \
                 mock.patch.object(declaration, "r_environment", return_value={}):
                declaration.verify(root, out)
                refs.write_text("instance,z\n1,15\n")
                with self.assertRaisesRegex(ValueError, "Comparison output changed"):
                    declaration.verify(root, out)
                refs.write_text("instance,z\n1,12\n")
                parent.write_text('{"frozen": false}\n')
                with self.assertRaisesRegex(ValueError, "Prior input/artifact changed"):
                    declaration.verify(root, out)
                parent.write_text('{"frozen": true}\n')
                receipt["reserve_evaluation_enabled"] = True
                receipt_path.write_text(json.dumps(receipt))
                with self.assertRaisesRegex(ValueError, "Invalid unexecuted"):
                    declaration.verify(root, out)


if __name__ == "__main__":
    unittest.main()
