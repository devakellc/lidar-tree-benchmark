#!/usr/bin/env python3
"""Complete the frozen detector matrix using the unchanged admitted pilot runner."""
import argparse
import copy
import csv
import json
import math
from pathlib import Path

import run_fgiemit_pilot as pilot
from fgiemit_comparison_lib import ARMS, PILOT, POLICIES
from prepare_fgiemit_development import DEVELOPMENT

REPO = Path(__file__).resolve().parents[1]
SUCCESS = ("successful_empty", "successful_nonempty")
NATIVE_FILES = ("model_io/predictions.laz", "model_io/predictions.laz.json",
                "model_io/sat_native/native_0.npz")


def read_json(path):
    return json.loads(path.read_text())


def key(cell):
    return cell["plot"], cell["arm"]


def code_hashes():
    return {"scripts/run_fgiemit_development.py": pilot.audit.file_hash(Path(__file__))}


def validate_success(cell, expected, directory):
    """Admission records must agree with their sealed metric files and support."""
    n = cell["predictions"]
    if (not isinstance(n, int) or isinstance(n, bool) or n < 0 or
            cell["state"] != ("successful_nonempty" if n else "successful_empty")):
        raise ValueError("Successful cell state differs from its prediction count")
    metrics = read_json(directory / "metrics.json")
    if cell["metrics"] != metrics:
        raise ValueError("Cell metrics differ from the sealed scoring output")
    execution = read_json(directory / "execution.json")
    if (execution["exit_code"] != 0 or
            execution["wall_seconds"] != cell["inference_wall_seconds"] or
            not math.isfinite(cell["inference_wall_seconds"]) or cell["inference_wall_seconds"] < 0):
        raise ValueError("Invalid successful execution receipt")
    policies = POLICIES[:1] if expected["arm"] == "chm_vwf" else POLICIES
    if [d["policy"] for d in metrics["detection"]] != list(policies):
        raise ValueError("Detection profiles differ from the frozen contract")
    for d in metrics["detection"]:
        tp, fp, fn = (d[k] for k in ("apex_TP", "apex_FP", "apex_FN"))
        if (any(type(v) is not int or v < 0 for v in (tp, fp, fn)) or
                tp + fp != n or tp + fn != expected["reference_count"]):
            raise ValueError("Detection counts differ from the declared support")
        f1 = 2 * tp / (n + expected["reference_count"])
        if not math.isfinite(d["apex_F1"]) or abs(d["apex_F1"] - f1) > .000051:
            raise ValueError("Detection rate differs from its counts")
    if expected["arm"] == "chm_vwf":
        if metrics["mask"] not in ({}, [], None):
            raise ValueError("CHM cannot supply instance masks")
    else:
        if not isinstance(metrics["mask"], list) or len(metrics["mask"]) != 1:
            raise ValueError("Require exactly one mask-scoring result")
        m = metrics["mask"][0]
        counts = [m[k] for k in ("TP", "FP", "FN", "n_pred", "n_ref")]
        if (any(type(v) is not int or v < 0 for v in counts) or
                m["n_pred"] != n or m["n_ref"] != expected["reference_count"] or
                m["TP"] + m["FP"] != n or m["TP"] + m["FN"] != m["n_ref"]):
            raise ValueError("Mask counts differ from the declared support")
        for category in "ABCD":
            ref, tp, fn = (m[k + category] for k in ("n_", "tp_", "fn_"))
            if any(type(v) is not int or v < 0 for v in (ref, tp, fn)) or tp + fn != ref:
                raise ValueError("Invalid category counts")
        if (sum(m["n_" + k] for k in "ABCD") != m["n_ref"] or
                sum(m["tp_" + k] for k in "ABCD") != m["TP"]):
            raise ValueError("Category support differs from the full denominator")
        for field, limit in (("sum_iou", m["TP"]), ("sum_maxiou", m["n_ref"])):
            if not math.isfinite(m[field]) or not 0 <= m[field] <= limit + .000051:
                raise ValueError("Invalid mask accumulator")


def preflight(root, pilot_dir, runtime_dir):
    pilot.verify(root, pilot_dir, runtime_dir)
    admitted = read_json(pilot_dir / "pilot.json")
    if not admitted["complete_pilot"] or any(c["state"] not in SUCCESS for c in admitted["cells"]):
        raise ValueError("Require a complete, successfully admitted pilot")
    matrix = read_json(root / "development_comparison/matrix.json")
    expected = [(p, a) for p in sorted(DEVELOPMENT) for a in ARMS]
    if ([key(c) for c in matrix["cells"]] != expected or
            any(c["pilot"] != (c["plot"] in PILOT) for c in matrix["cells"])):
        raise ValueError("Require the exact thirty-cell frozen detector matrix")
    lookup = {key(c): c for c in matrix["cells"]}
    for cell in admitted["cells"]:
        validate_success(cell, lookup[key(cell)], pilot_dir / cell["plot"] / cell["arm"])
    return matrix, admitted


def records_for(matrix, admitted, root, out, pilot_dir):
    reused = {key(c): c for c in admitted["cells"]}
    records = []
    for expected in matrix["cells"]:
        cell = (copy.deepcopy(reused[key(expected)]) if expected["pilot"] else
                dict(plot=expected["plot"], arm=expected["arm"], state="planned",
                     reference_count=expected["reference_count"]))
        source = pilot_dir if expected["pilot"] else out
        cell.update(origin="pilot" if expected["pilot"] else "new",
                    source_directory=str((source / cell["plot"] / cell["arm"]).relative_to(root)))
        records.append(cell)
    return records


def output_hashes(out, matrix):
    files = []
    for cell in matrix["cells"]:
        if cell["pilot"]:
            continue
        directory = out / cell["plot"] / cell["arm"]
        if directory.exists():
            files.extend(p for p in directory.iterdir() if p.is_file())
            files.extend(directory / name for name in NATIVE_FILES if (directory / name).exists())
    return {str(p.relative_to(out)): pilot.audit.file_hash(p) for p in sorted(files)}


def validate_records(receipt, matrix, admitted, root, out, pilot_dir):
    records = receipt["cells"]
    expected_records = records_for(matrix, admitted, root, out, pilot_dir)
    if len(records) != 30 or [key(c) for c in records] != [key(c) for c in expected_records]:
        raise ValueError("Missing, duplicate or reordered detector cells")
    stopped = False
    for actual, baseline, expected in zip(records, expected_records, matrix["cells"]):
        if any(actual[k] != baseline[k] for k in
               ("origin", "source_directory", "reference_count")):
            raise ValueError("Changed cell origin, source path or reference support")
        if baseline["origin"] == "pilot":
            if actual != baseline:
                raise ValueError("Reused pilot records must remain identical")
            continue
        state = actual["state"]
        if state not in (*SUCCESS, "planned", "failed") or (stopped and state != "planned"):
            raise ValueError("Invalid new-cell state or expansion after failure")
        stopped = stopped or state in ("planned", "failed")
        if state in SUCCESS:
            validate_success(actual, expected, root / actual["source_directory"])
        elif any(k in actual for k in ("predictions", "metrics", "resources")):
            raise ValueError("Unsuccessful cells cannot supply accepted results")
        if state == "failed" and not actual.get("error"):
            raise ValueError("Failed cells must record the error")
    complete = all(c["state"] in SUCCESS for c in records)
    if receipt["complete_detector_matrix"] != complete:
        raise ValueError("Detector completeness differs from the cell states")
    if receipt["expansion_stopped"] != any(c["state"] == "failed" for c in records):
        raise ValueError("Failure state differs from the expansion guard")


def run(root, out, pilot_dir, runtime_dir):
    if out.parent != root or out.exists():
        raise ValueError("Use a new immediate output directory; no retries or overwrites")
    matrix, admitted = preflight(root, pilot_dir, runtime_dir)
    parents = (pilot_dir / "pilot.json", runtime_dir / "runtime.json",
               root / "development_comparison/declaration.json", root / "development_comparison/matrix.json")
    _, protected = pilot.audit.workspace_inventory(root, out)
    out.mkdir()
    receipt = dict(schema_version=1, stage="development_detector_matrix",
        parent_sha256={str(p): pilot.audit.file_hash(p) for p in parents},
        protected_sha256=protected, orchestrator_sha256=code_hashes(),
        execution_code_sha256=pilot.code_hashes(), pilot_directory=str(pilot_dir),
        runtime_directory=str(runtime_dir), cells=records_for(matrix, admitted, root, out, pilot_dir),
        execution_order=[list(key(c)) for c in matrix["cells"] if not c["pilot"]],
        calibration_fitted=False, reserve_evaluation_enabled=False,
        complete_detector_matrix=False, expansion_stopped=False)
    manifest = out / "run.json"
    pilot.write_json(manifest, receipt)
    gpu = Path(read_json(root / "development_checkpoint_provenance_v2.json")["gpu_root"])
    with (root / "development_comparison/reference_apexes.csv").open() as stream:
        references = list(csv.DictReader(stream))
    for expected, record in zip(matrix["cells"], receipt["cells"]):
        if expected["pilot"]:
            continue
        directory = root / record["source_directory"]
        directory.mkdir(parents=True)
        record["state"] = "running"
        pilot.write_json(manifest, receipt)
        print("Running", *key(record), flush=True)
        try:
            result = pilot.run_cell(expected, directory, root, gpu, runtime_dir, references)
            candidate = dict(record, **result)
            validate_success(candidate, expected, directory)
            record.update(result)
        except (Exception, KeyboardInterrupt) as error:
            record.update(state="failed", error=f"{type(error).__name__}: {error}")
            receipt["expansion_stopped"] = True
            print("Stopped:", record["error"], flush=True)
            break
        finally:
            pilot.write_json(manifest, receipt)
    receipt["output_sha256"] = output_hashes(out, matrix)
    receipt["complete_detector_matrix"] = all(c["state"] in SUCCESS for c in receipt["cells"])
    pilot.write_json(manifest, receipt)
    verify(root, out, pilot_dir, runtime_dir)
    return receipt["complete_detector_matrix"]


def verify(root, out, pilot_dir, runtime_dir):
    matrix, admitted = preflight(root, pilot_dir, runtime_dir)
    receipt = read_json(out / "run.json")
    if (receipt["schema_version"] != 1 or receipt["stage"] != "development_detector_matrix" or
            receipt["calibration_fitted"] or receipt["reserve_evaluation_enabled"] or
            out.parent != root or receipt["pilot_directory"] != str(pilot_dir) or
            receipt["runtime_directory"] != str(runtime_dir) or
            receipt["execution_order"] != [list(key(c)) for c in matrix["cells"] if not c["pilot"]]):
        raise ValueError("Invalid development execution scope")
    if (receipt["orchestrator_sha256"] != code_hashes() or
            receipt["execution_code_sha256"] != pilot.code_hashes() or
            receipt["execution_code_sha256"] != admitted["code_sha256"] or
            receipt["output_sha256"] != output_hashes(out, matrix)):
        raise ValueError("Changed runner, pilot compatibility or accepted outputs")
    validate_records(receipt, matrix, admitted, root, out, pilot_dir)
    for path, expected in receipt["parent_sha256"].items():
        if pilot.audit.file_hash(Path(path)) != expected:
            raise ValueError("Development execution parent changed")
    for name, expected in receipt["protected_sha256"].items():
        if pilot.audit.file_hash(root / name) != expected:
            raise ValueError("Protected prior artifact changed")
    print("Detector matrix, unchanged pilot reuse and protected artifacts verified", flush=True)
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("root", "out", "pilot", "runtime"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    paths = (args.root.resolve(strict=True), args.out.resolve(),
             args.pilot.resolve(strict=True), args.runtime.resolve(strict=True))
    if args.verify:
        verify(*paths)
    elif not run(*paths):
        raise SystemExit(1)
