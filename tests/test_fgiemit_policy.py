"""Policy freezes must preserve selection, reserve scope and uncertain overlap."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import freeze_fgiemit_policy as policy


def fixture():
    declaration = dict(development=sorted(policy.development.DEVELOPMENT),
        evaluation_reserve=list(policy.RESERVE), historical_test=["1002", "1004", "1008", "1012", "1018", "1028"],
        source_md5={"training.zip": "a" * 32, "plot_data.yaml": "b" * 32},
        source_sha256={f"source/training/plot_{p}.las": "c" * 64 for p in policy.RESERVE})
    evidence = policy.development.read_json(policy.REPO / policy.SOURCES)
    provenance = dict(checkpoint_identity_verified=True, FGI_EMIT_training_overlap="unknown",
        exhaustive_training_plot_manifest_available=False,
        segmentanytree=dict(sha256=evidence["checkpoint_sha256"]["segmentanytree"]),
        forestformer3d=dict(sha256=evidence["checkpoint_sha256"]["forestformer3d"], archive_md5="d" * 32,
            upstream_committed_split_lists={s: [f"NIBIO_{i}" for i in range(n)]
                for s, n in (("train", 47), ("val", 16), ("test", 28))}))
    matrix = dict(cells=[dict(plot=p, arm=a, config=dict(checkpoint_sha256=provenance[a]["sha256"],
        layout="whole_scene" if a == "forestformer3d" else "existing_upstream_pipeline",
        additional_score_cutoff=None, passes=1)) for p in declaration["development"] for a in policy.ARMS[1:]],
        primary_mask=dict(iou=.5, min_points=40, min_raw_Z_extent_m=1.5),
        detection=dict(xy_m=4, absolute_z_m=5, default_policy="max_agl"), timeout_seconds=3600)
    receipt = dict(complete_calibration_matrix=True, declared_cells=50, reserve_evaluation_enabled=False,
        threshold_selected=False, fusion_enabled=False, deployment_lookup_exported=False)
    pooled = [dict(arm=a, target=t, n_cells="10", n_ref="841", n_pred="800",
        TP=str(tp), FP=str(800-tp), FN=str(841-tp), F1="ignored")
        for a,t,tp in (("chm_vwf","apex_max_agl",300), ("segmentanytree","apex_max_agl",600),
                      ("forestformer3d","apex_max_agl",675), ("segmentanytree","mask_iou_0.5",500),
                      ("forestformer3d","mask_iou_0.5",595))]
    inventory = [dict(plot=p, role="evaluation_reserve", n_all=str(n), header_points="5500000",
        prior_audit="False", workspace_evidence_files="0") for p,n in zip(policy.RESERVE, policy.RESERVE_COUNTS)]
    return declaration, matrix, provenance, receipt, pooled, inventory, evidence


class PolicyTests(unittest.TestCase):
    def test_selected_single_arm_keeps_controls_and_unvalidated_reserve_explicit(self):
        args = fixture()
        frozen, plan = policy.build_policy(*args)
        self.assertEqual(frozen["selected_arm"], "forestformer3d")
        self.assertEqual(frozen["controls"], ["chm_vwf", "segmentanytree"])
        self.assertEqual(len(plan), 9)
        self.assertEqual(sum(c["role"] == "selected_policy" for c in plan), 3)
        self.assertEqual(sum(c["reference_count"] for c in plan if c["arm"] == "forestformer3d"), 257)
        self.assertTrue(all(c["frdens"] is None and c["pdens"] is None for c in plan))
        self.assertTrue(all(c["state"] == "planned_input_validation_required" for c in plan))
        self.assertFalse(frozen["reserve_evaluation_enabled"])
        self.assertFalse(frozen["independent_unseen_data_claim_enabled"])
        self.assertIsNone(frozen["additional_score_cutoff"])
        self.assertEqual(frozen["ensemble_members"], [])
        self.assertEqual(frozen["development_baselines"][0]["F1"], 600 / 1641)
        # Policy snapshots cannot mutate a sealed parent object.
        frozen["mask_scoring"]["iou"] = .9
        self.assertEqual(args[1]["primary_mask"]["iou"], .5)

    def test_incomplete_support_or_changed_counts_cannot_supply_selection(self):
        for change in ("incomplete", "duplicate", "counts", "reference", "not_stronger"):
            args = copy.deepcopy(fixture())
            if change == "incomplete": args[4].pop()
            elif change == "duplicate": args[4][0] = args[4][1]
            elif change == "counts": args[4][0]["FP"] = "1"
            elif change == "reference": args[4][0]["n_ref"] = "840"
            else: args[4][2].update(TP="1", FP="799", FN="840")
            with self.subTest(change=change), self.assertRaises(ValueError):
                policy.build_policy(*args)

    def test_reserve_replacement_prior_use_or_configuration_drift_is_rejected(self):
        for change in ("replacement", "prior", "population", "config", "calibration"):
            args = copy.deepcopy(fixture())
            if change == "replacement": args[0]["evaluation_reserve"][0] = "1002"
            elif change == "prior": args[5][0]["workspace_evidence_files"] = "1"
            elif change == "population": args[5][0]["n_all"] = "53"
            elif change == "config": args[1]["cells"][0]["config"]["passes"] = 2
            else: args[3]["complete_calibration_matrix"] = False
            with self.subTest(change=change), self.assertRaises(ValueError):
                policy.build_policy(*args)

    def test_archived_source_identity_and_unknown_overlap_are_required(self):
        declaration, _, provenance, *_, evidence = fixture()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / "docs").mkdir()
            blobs = {n: b"archived paper fixture" for n in evidence["sources"]}
            for split, rows in provenance["forestformer3d"]["upstream_committed_split_lists"].items():
                blobs[f"ff3d-{split}.txt"] = ("\n".join(rows)+"\n").encode()
            blobs["sat-lfs.txt"] = ("oid sha256:" + provenance["segmentanytree"]["sha256"] + "\n").encode()
            blobs["ff3d-release.json"] = json.dumps(dict(files=[dict(key="clean_forestformer.zip", checksum="md5:"+"d"*32)])).encode()
            blobs["fgi-release.json"] = json.dumps(dict(files=[dict(key=n, checksum="md5:"+h)
                for n,h in declaration["source_md5"].items()])).encode()
            for name, blob in blobs.items():
                (root / name).write_bytes(blob)
                evidence["sources"][name].update(sha256=policy.hashes(root, [name])[name], bytes=len(blob))
            (root / policy.SOURCES).write_text(json.dumps(evidence))
            with mock.patch.object(policy, "REPO", root):
                result = policy.source_evidence(root, provenance, declaration)
                self.assertEqual(result["assessment"]["upstream_training_overlap"], "unknown")
                changed = copy.deepcopy(provenance)
                changed["FGI_EMIT_training_overlap"] = "absent"
                with self.assertRaisesRegex(ValueError, "overlap scope"):
                    policy.source_evidence(root, changed, declaration)
                changed = copy.deepcopy(provenance); changed["forestformer3d"]["sha256"] = "0" * 64
                with self.assertRaisesRegex(ValueError, "different weights"):
                    policy.source_evidence(root, changed, declaration)
                (root / "ff3d-train.txt").write_text("renamed training input\n")
                with self.assertRaisesRegex(ValueError, "source changed"):
                    policy.source_evidence(root, provenance, declaration)

    def test_freeze_replay_rejects_policy_edits_parent_drift_and_existing_outputs(self):
        frozen, plan = policy.build_policy(*fixture())
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); out = root / "policy"
            parents = {"calibration.json": "a" * 64}
            with mock.patch.object(policy, "preflight", return_value=(frozen, plan, parents)):
                receipt = policy.freeze(root, root / "calibration", root / "evidence", out)
                policy.freeze(root, root / "calibration", root / "evidence", out, verify=True)
                self.assertFalse(receipt["reserve_point_records_parsed"])
                with self.assertRaisesRegex(ValueError, "new immediate"):
                    policy.freeze(root, root / "calibration", root / "evidence", out)
                parents["calibration.json"] = "b" * 64
                with self.assertRaisesRegex(ValueError, "parents, code"):
                    policy.freeze(root, root / "calibration", root / "evidence", out, verify=True)
                changed = copy.deepcopy(frozen); changed["reserve_evaluation_enabled"] = True
                (out / "policy.json").write_text(json.dumps(changed))
                with self.assertRaisesRegex(ValueError, "Frozen policy differs"):
                    policy.freeze(root, root / "calibration", root / "evidence", out, verify=True)

    def test_failed_parent_preflight_cannot_leave_a_freeze_receipt(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); out = root / "policy"
            with mock.patch.object(policy, "preflight", side_effect=ValueError("changed calibration")), \
                    self.assertRaisesRegex(ValueError, "changed calibration"):
                policy.freeze(root, root / "calibration", root / "evidence", out)
            self.assertFalse(out.exists())


if __name__ == "__main__":
    unittest.main()
