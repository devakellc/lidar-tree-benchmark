#!/usr/bin/env python3
"""Validate the frozen reserve and seal its execution contract; no inference."""
import argparse
import copy
import json
import math
from pathlib import Path
import subprocess
import sys
import time

import laspy
import numpy as np
import scipy
import yaml

import freeze_fgiemit_policy as policy
import prepare_fgiemit_development as inputs
from fgiemit_comparison_lib import apex_profiles, chm_parameters

REPO = Path(__file__).resolve().parents[1]
CODE = ("scripts/prepare_fgiemit_reserve.py", "docs/fgiemit-reserve-input-protocol.md",
        *inputs.CODE_FILES, "scripts/fgiemit_comparison_lib.py")
read_json = policy.development.read_json
write_json = policy.development.pilot.write_json
file_hash = inputs.audit.file_hash


def check_location(root, out, creating=False):
    if root != root.resolve() or out != out.resolve():
        raise ValueError("Require resolved data and output paths")
    if out.is_relative_to(root) or root.is_relative_to(out):
        raise ValueError("Reserve output must be outside the sealed development root")
    if creating and out.exists():
        raise ValueError("Use a fresh reserve directory; preserve every prior attempt")


def preflight(root):
    directory = root / "development_policy"
    receipt = read_json(directory / "freeze.json")
    policy.freeze(root, Path(receipt["calibration_directory"]),
                  Path(receipt["evidence_directory"]), directory, verify=True)
    frozen = read_json(directory / "policy.json")
    declaration = read_json(root / "development_declaration/declaration.json")
    plan = policy.calibration.read_csv(directory / "reserve_plan.csv")
    calibration = read_json(Path(receipt["calibration_directory"]) / "calibration.json")
    runtime = Path(calibration["runtime_directory"])
    return dict(policy=frozen, plan=plan, declaration=declaration,
        parent_sha256=policy.hashes(directory, ("freeze.json", "policy.json", "reserve_plan.csv")),
        runtime_directory=str(runtime), runtime_sha256=file_hash(runtime / "runtime.json"),
        execution_code_sha256=policy.development.pilot.code_hashes(),
        normalization=read_json(root / "development_inputs/1001/normalization.json"))


def source_for(root, context, plot):
    # Check scope and declared bytes before any point reader is called.
    if plot not in policy.RESERVE:
        raise ValueError("Only original reserve plots may be opened")
    relative = f"source/training/plot_{plot}.las"
    path = root / relative
    if (path.is_symlink() or not path.resolve().is_relative_to(root) or
            file_hash(path) != context["declaration"]["source_sha256"][relative]):
        raise ValueError("Reserve source changed or escaped the source root")
    return path


def check_support(plot, info, context):
    planned = [r for r in context["plan"] if r["plot"] == plot]
    if (plot not in policy.RESERVE or len(planned) != 3 or
            [r["arm"] for r in planned] != list(policy.ARMS) or
            any(int(r["reference_count"]) != info["reference_trees"] or
                int(r["header_points"]) != info["source_points"] for r in planned) or
            info["reference_trees"] != policy.RESERVE_COUNTS[policy.RESERVE.index(plot)] or
            info["coordinate_frame"] != f"FGI-EMIT/19351234/plot_{plot}" or
            info["density_basis"] != "original_retained_returns_over_retained_XY_convex_hull" or
            info["declared_crs"] is not None or info["independent_AGL_validated"]):
        raise ValueError("Reserve support differs from the frozen population")
    n, first, area = info["retained_points"], info["first_returns"], info["footprint_area_m2"]
    if (not math.isfinite(area) or area <= 0 or not 0 < first <= n or
            n + info["excluded_class5"] != info["source_points"] or
            info["frdens"] != first / area or info["pdens"] != n / area):
        raise ValueError("Reserve density must use measured original retained returns")
    chm_parameters(info["frdens"], info["pdens"])


def check_model_fields(cloud, normalized=False):
    if (set(cloud.point_format.extra_dimension_names) != {"source_row"} or
            cloud.header.parse_crs() is not None or
            not np.isin(cloud.classification, [1, 2] if normalized else [1]).all()):
        raise ValueError("Model input contains annotations or unexpected classification/CRS")
    permitted = {"X", "Y", "Z", "return_number", "number_of_returns", "classification", "source_row"}
    for name in cloud.point_format.dimension_names:
        if name not in permitted and np.any(cloud[name] != 0):
            raise ValueError(f"Model input leaks an unused source field: {name}")


def inspect_prepared(source, keep, rows, metadata, directory, context):
    raw = laspy.read(directory / "geometry.las")
    reference = laspy.read(directory / "reference.laz")
    normalized = laspy.read(directory / "normalized.laz")
    inputs.verify_geometry(source, raw, rows)
    inputs.verify_geometry(source, reference, rows)
    for name in ("classification", "tree_index", "edge", "dead"):
        if not np.array_equal(np.asarray(source[name])[keep], reference[name]):
            raise ValueError(f"Reserve reference changed {name}")
    check_model_fields(raw)
    check_model_fields(normalized, normalized=True)
    stats, heights = inputs.normalization_diagnostics(raw, normalized, reference.tree_index, metadata)
    normalization = read_json(directory / "normalization.json")
    expected = dict(context["normalization"], rows=len(rows), ground_points=stats["ground_points"])
    if normalization != expected:
        raise ValueError("Reserve normalization method, versions or support changed")
    profiles = apex_profiles(np.column_stack((raw.x, raw.y, raw.z)),
        np.column_stack((normalized.x, normalized.y, normalized.z)), reference.tree_index, rows)
    if (len(profiles) != 3 * len(metadata["trees"]) or
            {r["instance"] for r in profiles} != {int(k) for k in metadata["trees"]}):
        raise ValueError("Reserve reference profiles changed the population")
    for row in profiles:
        row.update(plot=directory.name, coordinate_frame=f"FGI-EMIT/19351234/plot_{directory.name}",
                   category=metadata["trees"][row["instance"]]["c"])
    return stats, heights, profiles


def build_contract(context, results, outputs):
    if ([r["plot"] for r in results] != list(policy.RESERVE) or
            any(r["status"] != "validated_structure" for r in results)):
        raise ValueError("Every original reserve plot must pass before sealing execution")
    frozen = context["policy"]
    cells = []
    for row in results:
        plot = row["plot"]
        check_support(plot, row, context)
        for arm in policy.ARMS:
            name = f"inputs/{plot}/{'normalized.laz' if arm == 'chm_vwf' else 'geometry.las'}"
            cells.append(dict(plot=plot, arm=arm, rung="native", state="planned",
                role="selected_policy" if arm == frozen["selected_arm"] else "fixed_control",
                coordinate_frame=row["coordinate_frame"], input=name, input_sha256=outputs[name],
                reference=f"inputs/{plot}/reference.laz",
                reference_sha256=outputs[f"inputs/{plot}/reference.laz"],
                normalized=f"inputs/{plot}/normalized.laz",
                normalized_sha256=outputs[f"inputs/{plot}/normalized.laz"],
                reference_count=row["reference_trees"], retained_points=row["retained_points"],
                frdens=row["frdens"], pdens=row["pdens"],
                config=chm_parameters(row["frdens"], row["pdens"]) if arm == "chm_vwf" else
                    copy.deepcopy(frozen["instance_configurations"][arm]),
                mask_track=arm != "chm_vwf", detection_track=True))
    if [[r["plot"], r["arm"]] for r in cells] != frozen["inference"]["order"]:
        raise ValueError("Frozen inference order changed")
    return dict(schema_version=1, protocol="fgiemit-reserve-execution-v1", cells=cells,
        selected_arm=frozen["selected_arm"], primary_mask=copy.deepcopy(frozen["mask_scoring"]),
        detection=copy.deepcopy(frozen["apex_scoring"]), inference=copy.deepcopy(frozen["inference"]),
        reporting=copy.deepcopy(frozen["reporting"]),
        reference_apexes="contract/reference_apexes.csv", reference_count=257,
        planned_detector_cells=9, planned_primary_scoring_cells=15,
        runtime_directory=context["runtime_directory"], runtime_sha256=context["runtime_sha256"],
        execution_core_sha256=context["execution_code_sha256"],
        model_mounts="cell_input_only_read_only_no_reference_or_parent_data_root",
        output_location="new_sibling_directory_outside_sealed_development_root",
        required_runner="reserve_scope_guard_and_contract_replay_before_any_cell",
        cell_outcomes=["missing", "failed", "completed_empty", "completed"],
        confidence_output="raw_feature_only", calibration_fitted=False,
        prospective_claim=frozen["prospective_claim"], upstream_training_overlap="unknown",
        independent_unseen_data_claim_enabled=False, independent_AGL_validated=False,
        inputs_validated=True, runner_validated=False, execution_enabled=False, inference_run=False)


def output_hashes(out):
    paths = sorted(out.rglob("*"))
    if any(p.is_symlink() for p in paths):
        raise ValueError("Reserve artifacts must be direct files, not symlinks")
    return {str(p.relative_to(out)): file_hash(p) for p in paths
            if p.is_file() and p != out / "manifest.json"}


def csv_rows(rows):
    return [{k: "" if v is None else str(v) for k, v in r.items()} for r in rows]


def summary_rows(results):
    fields = list(dict.fromkeys(k for r in results for k in r))
    return [{k: r.get(k, "") for k in fields} for r in results]


def prepare(root, out, rscript="Rscript"):
    check_location(root, out, creating=True)
    context = preflight(root)
    code = policy.hashes(REPO, CODE)
    metadata = yaml.safe_load((root / "source/plot_data.yaml").read_text())
    out.mkdir()
    (out / "inputs").mkdir()
    results, profiles = [], []
    for plot in policy.RESERVE:
        directory = out / "inputs" / plot
        directory.mkdir()
        started = time.monotonic()
        result = dict(plot=plot, status="failed", error="")
        try:
            source = laspy.read(source_for(root, context, plot))
            keep, rows, info = inputs.validate_points(source, metadata[int(plot)])
            info["coordinate_frame"] = f"FGI-EMIT/19351234/plot_{plot}"
            check_support(plot, info, context)
            inputs.export_inputs(source, keep, rows, directory)
            write_json(directory / "support.json", info)
            command = [rscript, str(REPO / "scripts/normalize_fgiemit_development.R"),
                str(directory / "geometry.las"), str(directory / "normalized.laz"),
                str(directory / "normalization.json")]
            write_json(directory / "command.json", dict(argv=command, timeout_seconds=600))
            with (directory / "normalization.log").open("w") as log:
                subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=600)
            stats, heights, plot_profiles = inspect_prepared(source, keep, rows,
                metadata[int(plot)], directory, context)
            inputs.write_csv(directory / "height_diagnostics.csv", heights)
            profiles.extend(plot_profiles)
            result.update({k: v for k, v in info.items() if not isinstance(v, (dict, list))})
            result.update(stats, status="validated_structure")
            del source, keep, rows
        except Exception as error:
            result["error"] = f"{type(error).__name__}: {error}"
        result["elapsed_seconds"] = time.monotonic() - started
        write_json(directory / "receipt.json", result)
        results.append(result)
        print(f"{plot}: {result['status']} {result['error']}", flush=True)
    # Replay parents after opening the reserve; do not weaken the old closed-reserve guards.
    if preflight(root) != context or policy.hashes(REPO, CODE) != code:
        raise ValueError("Preparation parents or code changed; outputs remain unsealed")
    inputs.write_csv(out / "summary.csv", summary_rows(results))
    complete = all(r["status"] == "validated_structure" for r in results)
    if complete:
        contract = build_contract(context, results, output_hashes(out))
        (out / "contract").mkdir()
        write_json(out / "contract/matrix.json", contract)
        inputs.write_csv(out / "contract/reference_apexes.csv", profiles)
    manifest = dict(schema_version=1, protocol="fgiemit-reserve-inputs-v1",
        development_root=str(root), output_directory=str(out), plots=list(policy.RESERVE),
        parent_sha256=context["parent_sha256"], code_sha256=code, results=results,
        output_sha256=output_hashes(out), complete_population=complete,
        execution_contract_sealed=complete, reserve_point_records_parsed=True,
        inference_run=False, calibration_fitted=False, execution_enabled=False,
        independent_AGL_validated=False, upstream_training_overlap="unknown",
        environment=dict(python=sys.version, numpy=np.__version__, scipy=scipy.__version__,
                         laspy=laspy.__version__, yaml=yaml.__version__))
    write_json(out / "manifest.json", manifest)
    return complete


def verify(root, out):
    check_location(root, out)
    manifest = read_json(out / "manifest.json")
    context = preflight(root)
    if (manifest["schema_version"] != 1 or manifest["protocol"] != "fgiemit-reserve-inputs-v1" or
            manifest["development_root"] != str(root) or manifest["output_directory"] != str(out) or
            manifest["plots"] != list(policy.RESERVE) or
            [r["plot"] for r in manifest["results"]] != list(policy.RESERVE) or
            manifest["parent_sha256"] != context["parent_sha256"] or
            manifest["code_sha256"] != policy.hashes(REPO, CODE) or
            manifest["output_sha256"] != output_hashes(out) or
            not manifest["reserve_point_records_parsed"] or
            any(manifest[k] for k in ("inference_run", "calibration_fitted", "execution_enabled",
                                      "independent_AGL_validated")) or
            manifest["upstream_training_overlap"] != "unknown"):
        raise ValueError("Reserve receipt, parents, code or artifacts changed")
    metadata = yaml.safe_load((root / "source/plot_data.yaml").read_text())
    profiles = []
    for result in manifest["results"]:
        plot = result["plot"]
        directory = out / "inputs" / plot
        if read_json(directory / "receipt.json") != result:
            raise ValueError("Reserve receipt disagrees with plot result")
        if result["status"] == "failed":
            if not result["error"]:
                raise ValueError("Failed preparation requires an explicit error")
            continue
        if result["status"] != "validated_structure" or result["error"]:
            raise ValueError("Unknown reserve preparation outcome")
        source = laspy.read(source_for(root, context, plot))
        keep, rows, info = inputs.validate_points(source, metadata[int(plot)])
        info["coordinate_frame"] = f"FGI-EMIT/19351234/plot_{plot}"
        check_support(plot, info, context)
        if read_json(directory / "support.json") != info:
            raise ValueError("Reserve support differs from original points")
        stats, heights, plot_profiles = inspect_prepared(source, keep, rows,
            metadata[int(plot)], directory, context)
        derived = {k: v for k, v in info.items() if not isinstance(v, (dict, list))}
        if (any(result[k] != v for k, v in {**derived, **stats}.items()) or
                policy.calibration.read_csv(directory / "height_diagnostics.csv") != csv_rows(heights)):
            raise ValueError("Reserve diagnostics differ from prepared points")
        profiles.extend(plot_profiles)
        del source, keep, rows
    complete = all(r["status"] == "validated_structure" for r in manifest["results"])
    if (manifest["complete_population"] != complete or manifest["execution_contract_sealed"] != complete or
            policy.calibration.read_csv(out / "summary.csv") != csv_rows(summary_rows(manifest["results"]))):
        raise ValueError("Reserve completeness or summary changed")
    if complete:
        expected = build_contract(context, manifest["results"], manifest["output_sha256"])
        if (read_json(out / "contract/matrix.json") != expected or
                policy.calibration.read_csv(out / "contract/reference_apexes.csv") != csv_rows(profiles)):
            raise ValueError("Reserve execution contract or references changed")
    elif (out / "contract").exists():
        raise ValueError("Failed inputs cannot have an execution contract")
    print(f"Reserve parents, point identity, diagnostics and contract verified; complete={complete}", flush=True)
    return complete


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path, help="Sealed development data root")
    parser.add_argument("--out", required=True, type=Path, help="New reserve root outside development data")
    parser.add_argument("--rscript", default="Rscript")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    root, out = args.root.resolve(strict=True), args.out.resolve()
    complete = verify(root, out) if args.verify else prepare(root, out, args.rscript)
    if not complete:
        raise SystemExit("Reserve preparation failed; preserved receipts do not admit execution")
