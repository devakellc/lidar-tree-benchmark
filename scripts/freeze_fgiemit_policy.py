#!/usr/bin/env python3
"""Freeze a development-selected policy and bounded reserve plan, without inference."""
import argparse
import copy
from pathlib import Path

import calibrate_fgiemit_development as calibration

development = calibration.development
REPO = Path(__file__).resolve().parents[1]
SOURCES = "docs/fgiemit-overlap-sources.json"
CODE = ("scripts/freeze_fgiemit_policy.py", SOURCES, "docs/fgiemit-frozen-policy.md")
RESERVE = ("1003", "1010", "1023")
RESERVE_COUNTS = (54, 155, 48)
ARMS = development.ARMS
GROUPS = {(a, t) for a in ARMS for t in
          (("apex_max_agl",) if a == "chm_vwf" else ("apex_max_agl", "mask_iou_0.5"))}


def hashes(base, names):
    return {name: development.pilot.audit.file_hash(base / name) for name in names}


def source_evidence(directory, provenance, declaration):
    """Check archived primary sources; names/dates alone never establish absence."""
    manifest = development.read_json(REPO / SOURCES)
    for name, record in manifest["sources"].items():
        if Path(name).name != name or (directory / name).is_symlink():
            raise ValueError("Require direct archived source files")
        if (development.pilot.audit.file_hash(directory / name) != record["sha256"] or
                (directory / name).stat().st_size != record["bytes"]):
            raise ValueError("Archived overlap source changed")
    if manifest["schema_version"] != 1 or manifest["assessment"] != dict(
            upstream_training_overlap="unknown", exhaustive_checkpoint_training_manifest=False,
            documented_FGI_EMIT_membership_found=False, independent_unseen_data_claim_supported=False,
            ff3d_committed_split_counts=dict(train=47, val=16, test=28),
            ff3d_paper_region_absent_from_committed_lists="BlueCat",
            rationale=manifest["assessment"]["rationale"]):
        raise ValueError("Overlap assessment requires a new reviewed policy version")
    if (provenance["FGI_EMIT_training_overlap"] != "unknown" or
            provenance["exhaustive_training_plot_manifest_available"] or
            not provenance["checkpoint_identity_verified"]):
        raise ValueError("Checkpoint overlap scope changed")
    for arm, digest in manifest["checkpoint_sha256"].items():
        if provenance[arm]["sha256"] != digest:
            raise ValueError("Overlap evidence belongs to different weights")
    for split, count in manifest["assessment"]["ff3d_committed_split_counts"].items():
        rows = (directory / f"ff3d-{split}.txt").read_text().splitlines()
        if (rows != provenance["forestformer3d"]["upstream_committed_split_lists"][split] or
                len(rows) != count or any("bluecat" in r.lower() for r in rows)):
            raise ValueError("Committed split evidence differs from installed provenance")
    pointer = (directory / "sat-lfs.txt").read_text().splitlines()
    if "oid sha256:" + provenance["segmentanytree"]["sha256"] not in pointer:
        raise ValueError("SAT upstream LFS identity differs")
    release = development.read_json(directory / "ff3d-release.json")
    files = {f["key"]: f["checksum"] for f in release["files"]}
    if files["clean_forestformer.zip"] != "md5:" + provenance["forestformer3d"]["archive_md5"]:
        raise ValueError("FF3D release identity differs")
    release = development.read_json(directory / "fgi-release.json")
    files = {f["key"]: f["checksum"] for f in release["files"]}
    if any(files[name] != "md5:" + md5 for name, md5 in declaration["source_md5"].items()):
        raise ValueError("FGI release identity differs")
    return manifest


def build_policy(declaration, matrix, provenance, receipt, pooled, inventory, evidence):
    if (declaration["development"] != sorted(development.DEVELOPMENT) or
            declaration["evaluation_reserve"] != list(RESERVE) or
            set(declaration["historical_test"]) & (set(RESERVE) | development.DEVELOPMENT)):
        raise ValueError("Development, reserve or historical split changed")
    if (not receipt["complete_calibration_matrix"] or receipt["declared_cells"] != 50 or
            receipt["reserve_evaluation_enabled"] or receipt["threshold_selected"] or
            receipt["fusion_enabled"] or receipt["deployment_lookup_exported"]):
        raise ValueError("Require completed calibration with the reserve still closed")
    # Select explicitly once, using complete development evidence. No tuning API.
    scores = [r for r in pooled if (r["arm"], r["target"]) in GROUPS]
    if (len(scores) != 5 or {(r["arm"], r["target"]) for r in scores} != GROUPS or
            any(int(r["n_cells"]) != 10 or int(r["n_ref"]) != 841 for r in scores)):
        raise ValueError("Selection requires complete equal development support")
    baseline = [dict(arm=r["arm"], target=r["target"],
        **{k: int(r[k]) for k in ("n_pred", "n_ref", "TP", "FP", "FN")}) for r in scores]
    for row in baseline:
        if (min(row[k] for k in ("n_pred", "n_ref", "TP", "FP", "FN")) < 0 or
                row["TP"] + row["FP"] != row["n_pred"] or
                row["TP"] + row["FN"] != row["n_ref"]):
            raise ValueError("Invalid pooled baseline counts")
        row["F1"] = 2 * row["TP"] / (row["n_pred"] + row["n_ref"])
    for target in ("apex_max_agl", "mask_iou_0.5"):
        group = {r["arm"]: r["F1"] for r in baseline if r["target"] == target}
        if any(group["forestformer3d"] <= v for a, v in group.items() if a != "forestformer3d"):
            raise ValueError("Frozen selection rationale no longer matches development evidence")
    configs = {}
    for arm in ARMS[1:]:
        cells = [c for c in matrix["cells"] if c["arm"] == arm]
        if (len(cells) != 10 or {c["plot"] for c in cells} != development.DEVELOPMENT or
                any(c["config"] != cells[0]["config"] for c in cells)):
            raise ValueError("Instance configuration differs across development plots")
        configs[arm] = copy.deepcopy(cells[0]["config"])
        if configs[arm]["checkpoint_sha256"] != provenance[arm]["sha256"]:
            raise ValueError("Model configuration and provenance disagree")
    reserve = [r for r in inventory if r["role"] == "evaluation_reserve"]
    if ([r["plot"] for r in reserve] != list(RESERVE) or
            [int(r["n_all"]) for r in reserve] != list(RESERVE_COUNTS) or
            any(r["prior_audit"] != "False" or int(r["workspace_evidence_files"]) != 0
                for r in reserve)):
        raise ValueError("Reserve metadata, counts or prior-use evidence changed")
    plan = []
    for row in reserve:
        for arm in ARMS:
            source = f"source/training/plot_{row['plot']}.las"
            plan.append(dict(plot=row["plot"], arm=arm,
                role="selected_policy" if arm == "forestformer3d" else "fixed_control",
                reference_count=int(row["n_all"]), header_points=int(row["header_points"]),
                source_sha256=declaration["source_sha256"][source],
                coordinate_frame=f"FGI-EMIT/19351234/plot_{row['plot']}",
                state="planned_input_validation_required", frdens=None, pdens=None))
    policy = dict(schema_version=1, policy="fgiemit_native_single_arm_v1",
        selection_stage="after_development_before_reserve_point_validation",
        selected_arm="forestformer3d", selected_targets=["apex_max_agl", "mask_iou_0.5"],
        controls=["chm_vwf", "segmentanytree"], rung="native", ensemble_members=[],
        additional_score_cutoff=None, calibration_used_for_filtering=False,
        confidence_output="raw_feature_only", deployment_lookup_exported=False,
        selection_rationale="stronger_observed_apex_and_mask_F1_on_complete_development_support",
        development_baselines=baseline, development_plots=declaration["development"],
        reserve_plots=list(RESERVE), historical_test_plots=declaration["historical_test"],
        instance_configurations=configs,
        chm_configuration_rule="sealed_fgiemit_comparison_lib.chm_parameters(frdens,pdens)",
        mask_scoring=copy.deepcopy(matrix["primary_mask"]),
        apex_scoring=copy.deepcopy(matrix["detection"]),
        input_preparation="unchanged_development_structure_and_geometric_AGL_contract",
        density_rule="measure_retained_original_returns_over_XY_convex_hull_no_upsampling",
        support="classes_0_to_4_all_references_including_edge_dead_and_short",
        matching="unchanged_one_to_one_matchers", preserve_full_source_rows=True,
        inference=dict(order=[[c["plot"], c["arm"]] for c in plan], concurrency=1,
            timeout_seconds=matrix["timeout_seconds"], attempts_per_cell=1,
            stop_on_first_failure=True, automatic_retries=False, fallback_tiling=False,
            checkpoint_or_parameter_rescue=False, selection_after_reserve=False),
        reporting=dict(pool_counts_before_rates=True, require_all_declared_cells=True,
            preserve_failed_missing_and_completed_empty=True, primary_targets=["apex_max_agl", "mask_iou_0.5"],
            keep_height_diagnostics_separate=True, report_original_AD_categories=True,
            per_plot_counts_required=True, reserve_bootstrap="not_primary_with_only_three_plots"),
        overlap_assessment=copy.deepcopy(evidence["assessment"]),
        prospective_claim="conditional_within_dataset_policy_evaluation_unknown_upstream_overlap",
        independent_unseen_data_claim_enabled=False,
        reserve_input_validation_required=True, reserve_execution_contract_required=True,
        reserve_output_location="separate_job_root_outside_the_sealed_development_data_root",
        reserve_evaluation_enabled=False, inference_run=False, calibration_fitted=False)
    return policy, plan


def preflight(root, calibration_dir, evidence_dir):
    parent = development.read_json(calibration_dir / "calibration.json")
    calibration.verify(root, Path(parent["run_directory"]), Path(parent["pilot_directory"]),
                       Path(parent["runtime_directory"]), Path(parent["summary_directory"]), calibration_dir)
    declaration = development.read_json(root / "development_declaration/declaration.json")
    provenance = development.read_json(root / "development_checkpoint_provenance_v2.json")
    evidence = source_evidence(evidence_dir, provenance, declaration)
    policy, plan = build_policy(declaration,
        development.read_json(root / "development_comparison/matrix.json"), provenance, parent,
        calibration.read_csv(Path(parent["summary_directory"]) / "pooled.csv"),
        calibration.read_csv(root / "development_declaration/plot_inventory.csv"), evidence)
    names = (str((calibration_dir / "calibration.json").relative_to(root)),
             "development_declaration/declaration.json", "development_comparison/matrix.json",
             "development_checkpoint_provenance_v2.json")
    return policy, plan, hashes(root, names)


def freeze(root, calibration_dir, evidence_dir, out, verify=False):
    if out.parent != root or (not verify and out.exists()):
        raise ValueError("Use a new immediate policy directory; preserve previous freezes")
    policy, plan, parents = preflight(root, calibration_dir, evidence_dir)
    if not verify:
        out.mkdir()
        development.pilot.write_json(out / "policy.json", policy)
        calibration.summary.write_csv(out / "reserve_plan.csv", plan)
    if development.read_json(out / "policy.json") != policy:
        raise ValueError("Frozen policy differs from the declared development decision")
    expected = [{k: "" if v is None else str(v) for k, v in r.items()} for r in plan]
    if calibration.read_csv(out / "reserve_plan.csv") != expected:
        raise ValueError("Frozen reserve plan changed")
    receipt = dict(schema_version=1, stage="development_policy", parent_sha256=parents,
        calibration_directory=str(calibration_dir), evidence_directory=str(evidence_dir),
        code_sha256=hashes(REPO, CODE), output_sha256=hashes(out, ("policy.json", "reserve_plan.csv")),
        selected_arm="forestformer3d", declared_detector_cells=9, declared_scoring_cells=15,
        reserve_references=257, reserve_point_records_parsed=False,
        reserve_evaluation_enabled=False, inference_run=False, calibration_fitted=False)
    if verify:
        if development.read_json(out / "freeze.json") != receipt:
            raise ValueError("Changed frozen policy parents, code, evidence or outputs")
    else:
        development.pilot.write_json(out / "freeze.json", receipt)
    print("Frozen FF3D policy and nine-cell reserve plan verified; execution remains disabled", flush=True)
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("root", "calibration", "evidence", "out"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    paths = [getattr(args, name).resolve(strict=name != "out") for name in
             ("root", "calibration", "evidence", "out")]
    freeze(*paths, verify=args.verify)
