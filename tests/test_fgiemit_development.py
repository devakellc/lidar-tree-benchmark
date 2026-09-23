"""Metadata-only split and source-integrity tests; no models or real data."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import laspy
import yaml

SPEC = importlib.util.spec_from_file_location(
    "fgi_development", Path(__file__).resolve().parents[1] / "scripts/audit_fgiemit_development.py"
)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


def metadata():
    densities = {"1001": 1058, "1019": 28, "1013": 142, "1023": 169,
                 "1020": 219, "1031": 249, "1024": 315, "1003": 429,
                 "1005": 443, "1027": 488, "1009": 524, "1010": 789, "1022": 1695}
    densities.update({p: 500 for p in audit.TEST_PLOTS})
    return {int(p): dict(test=p in audit.TEST_PLOTS, density=v, area=0.126,
                        n_trees=dict(A=2, B=1, C=0, D=0, all=3)) for p, v in densities.items()}


def fixture(root):
    source = root / "source"
    (source / "training").mkdir(parents=True)
    (source / "plot_data.yaml").write_text(yaml.safe_dump(metadata()))
    header = laspy.LasHeader(point_format=7, version="1.4")
    header.add_extra_dim(laspy.ExtraBytesParams(name="tree_index", type="int32"))
    cloud = laspy.LasData(header)
    cloud.x = [0, 1, 2]; cloud.y = [0, 1, 2]; cloud.z = [0, 2, 3]
    cloud.return_number = [1, 1, 2]; cloud.number_of_returns = [1, 2, 2]
    with zipfile.ZipFile(source / "training.zip", "w") as archive:
        for row in audit.metadata_rows(metadata()):
            if row["publisher_split"] != "training":
                continue
            path = source / "training" / f"plot_{row['plot']}.las"
            cloud.write(path)
            archive.write(path, str(path.relative_to(source)))
    receipt = root / "training/runs/1001/receipt.json"
    receipt.parent.mkdir(parents=True)
    receipt.write_text('{"fixture": true}\n')
    return {name: audit.file_hash(source / name, "md5") for name in audit.RELEASE_MD5}


class DevelopmentAuditTests(unittest.TestCase):
    def test_declared_split_is_score_blind_and_keeps_observed_plots_out(self):
        rows = audit.metadata_rows(metadata())
        declared = audit.declare_split(rows, {"1001": ["receipt"], "1019": ["receipt"]})
        reserve = {r["plot"] for r in declared if r["role"] == "evaluation_reserve"}
        development = [r for r in declared if r["role"] == "development"]
        self.assertEqual(reserve, {"1003", "1010", "1023"})
        self.assertEqual(len(development), 10)
        self.assertTrue(audit.AUDITED_PLOTS <= {r["plot"] for r in development})
        self.assertEqual(len({r["development_fold"] for r in development}), 10)
        self.assertEqual(audit.declare_split(list(reversed(rows)), {}), list(reversed(
            audit.declare_split(rows, {}))))
        self.assertTrue(all(not r["evaluation_admitted"] for r in declared))

    def test_prior_processing_never_silently_changes_reserve(self):
        with self.assertRaisesRegex(ValueError, "Unexpected prior processing"):
            audit.declare_split(audit.metadata_rows(metadata()), {"1005": ["run"]})
        changed = metadata()
        changed[1003]["test"] = True
        with self.assertRaisesRegex(ValueError, "published split"):
            audit.declare_split(audit.metadata_rows(changed), {})

    def test_invalid_split_flags_and_counts_fail(self):
        changed = metadata(); changed[1001]["test"] = "false"
        with self.assertRaisesRegex(ValueError, "split flag"):
            audit.metadata_rows(changed)
        changed = metadata(); changed[1001]["n_trees"]["all"] = 4
        with self.assertRaisesRegex(ValueError, "counts disagree"):
            audit.metadata_rows(changed)

    def test_header_estimates_are_separate_from_admitted_density(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); fixture(root)
            path = root / "source/training/plot_1003.las"
            result = audit.audit_header(path, 0.126)
            self.assertEqual(result["header_points"], 3)
            self.assertEqual(result["header_first_returns"], 2)
            self.assertIsNone(result["declared_crs"])
            self.assertFalse(result["density_admitted"])
            self.assertAlmostEqual(result["estimated_pdens"], 3 / 1260)
            self.assertAlmostEqual(result["estimated_frdens"], 2 / 1260)
            self.assertEqual(result["height_datum"], "local_z_not_verified_AGL")

    def test_artifact_inventory_detects_runs_and_instance_files_without_reading_scores(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ("audit/attempt/runs/1003/ff/receipt.json",
                         "instances/sat/training/plot_1010.laz",
                         "source/training/plot_1023.las"):
                path = root / name; path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("not a score")
            evidence, protected = audit.workspace_inventory(root, root / "out")
            self.assertEqual(set(evidence), {"1003", "1010"})
            self.assertEqual(len(protected), 1)

    def test_audit_is_replayable_and_protects_sources_folds_and_previous_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); pins = fixture(root)
            out = root / "declaration"
            with patch.dict(audit.RELEASE_MD5, pins, clear=True):
                declaration = audit.run_audit(root, out)
                audit.verify(declaration, root)
                with self.assertRaisesRegex(ValueError, "new immediate child"):
                    audit.run_audit(root, out)
            folds = json.loads((out / "folds.json").read_text())
            self.assertEqual(len(folds), 10)
            for fold in folds:
                self.assertEqual(len(fold["calibration_plots"]), 9)
                self.assertNotIn(fold["validation_plot"], fold["calibration_plots"])
                self.assertFalse(audit.RESERVED_PLOTS.intersection(fold["calibration_plots"]))
                self.assertFalse(audit.TEST_PLOTS.intersection(fold["calibration_plots"]))
            self.assertFalse(declaration["inference_run"])
            self.assertFalse(declaration["scores_read"])
            self.assertFalse(declaration["point_records_parsed"])
            source = root / "source/training/plot_1003.las"
            source.write_bytes(source.read_bytes() + b"changed")
            with self.assertRaisesRegex(ValueError, "Protected input"):
                audit.verify(declaration, root)

    def test_extracted_file_must_match_immutable_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); pins = fixture(root)
            path = root / "source/training/plot_1001.las"
            path.write_bytes(path.read_bytes() + b"changed")
            with patch.dict(audit.RELEASE_MD5, pins, clear=True):
                with self.assertRaisesRegex(ValueError, "differs from pinned archive"):
                    audit.run_audit(root, root / "declaration")
            self.assertFalse((root / "declaration").exists())

    def test_replay_detects_new_reserve_processing_and_changed_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); pins = fixture(root); out = root / "declaration"
            with patch.dict(audit.RELEASE_MD5, pins, clear=True):
                declaration = audit.run_audit(root, out)
            prediction = root / "new_attempt/runs/1003/predictions.laz"
            prediction.parent.mkdir(parents=True)
            prediction.write_bytes(b"unapproved attempt")
            with self.assertRaisesRegex(ValueError, "reserve has processing evidence"):
                audit.verify(declaration, root)
            prediction.unlink()
            (out / "folds.json").write_text("[]\n")
            with patch("sys.argv", ["audit", "--root", str(root), "--out", str(out), "--verify"]):
                with self.assertRaisesRegex(ValueError, "Declaration output changed"):
                    audit.main()


if __name__ == "__main__":
    unittest.main()
