#!/usr/bin/env python3
"""Execute the nine frozen reserve cells once, preserving every failure."""
import argparse
from pathlib import Path

import prepare_fgiemit_reserve as inputs
import fgiemit_reserve_cell as engine
import run_fgiemit_development as development

REPO = Path(__file__).resolve().parents[1]
FILES = ("scripts/run_fgiemit_reserve.py", "scripts/fgiemit_reserve_cell.py",
         "docs/fgiemit-reserve-execution.md")
read_json, write_json = inputs.read_json, inputs.write_json
SUCCESS = development.SUCCESS


def preflight(root, prepared, out):
    inputs.check_location(root, prepared)
    inputs.check_location(root, out)
    if out.parent != prepared.parent or out == prepared:
        raise ValueError("Use a separate sibling output directory")
    if not inputs.verify(root, prepared):
        raise ValueError("Every reserve input must be validated")
    matrix = read_json(prepared / "contract/matrix.json")
    if ([(c["plot"], c["arm"]) for c in matrix["cells"]] !=
            [(p, a) for p in inputs.policy.RESERVE for a in inputs.policy.ARMS] or
            matrix["execution_core_sha256"] != development.pilot.code_hashes() or
            matrix["inference"] != dict(order=[[p, a] for p in inputs.policy.RESERVE
                for a in inputs.policy.ARMS], concurrency=1, timeout_seconds=3600,
                attempts_per_cell=1, stop_on_first_failure=True, automatic_retries=False,
                fallback_tiling=False, checkpoint_or_parameter_rescue=False,
                selection_after_reserve=False)):
        raise ValueError("Unexpected reserve execution contract")
    return matrix


def code_hashes():
    return inputs.policy.hashes(REPO, FILES)


def parents(prepared):
    return inputs.policy.hashes(prepared, ("manifest.json", "contract/matrix.json",
                                          "contract/reference_apexes.csv"))


def output_hashes(out, matrix):
    files = []
    for cell in matrix["cells"]:
        directory = out / cell["plot"] / cell["arm"]
        if directory.exists():
            files.extend(p for p in directory.iterdir() if p.is_file())
            files.extend(directory / p for p in development.NATIVE_FILES if (directory / p).exists())
    if any(p.is_symlink() or not p.resolve().is_relative_to(out) for p in files):
        raise ValueError("Accepted artifacts must be direct files inside the run")
    return {str(p.relative_to(out)): inputs.file_hash(p) for p in sorted(files)}


def validate_records(receipt, matrix, out):
    cells = receipt["cells"]
    if ([development.key(c) for c in cells] != [development.key(c) for c in matrix["cells"]]):
        raise ValueError("Missing, duplicate or reordered reserve cells")
    stopped = False
    for actual, expected in zip(cells, matrix["cells"]):
        state = actual["state"]
        if (actual["reference_count"] != expected["reference_count"] or
                actual["source_directory"] != str(out / actual["plot"] / actual["arm"]) or
                state not in (*SUCCESS, "planned", "failed") or
                (stopped and state != "planned")):
            raise ValueError("Invalid reserve state, support, path or execution after failure")
        stopped = stopped or state in ("planned", "failed")
        if state in SUCCESS:
            development.validate_success(actual, expected, Path(actual["source_directory"]))
        elif any(k in actual for k in ("predictions", "metrics", "resources")):
            raise ValueError("Unavailable reserve cells cannot supply accepted predictions")
        if state == "failed" and not actual.get("error"):
            raise ValueError("Failed reserve cells require an error")
    if (receipt["complete_detector_matrix"] != all(c["state"] in SUCCESS for c in cells) or
            receipt["expansion_stopped"] != any(c["state"] == "failed" for c in cells)):
        raise ValueError("Reserve completeness differs from recorded outcomes")


def run(root, prepared, out):
    if out.exists():
        raise ValueError("Preserve the existing attempt; no automatic retries or overwrite")
    matrix = preflight(root, prepared, out)
    out.mkdir()
    receipt = dict(schema_version=1, stage="fgiemit_reserve_execution_v1",
        development_root=str(root), prepared_directory=str(prepared),
        parent_sha256=parents(prepared), code_sha256=code_hashes(),
        cells=[dict(plot=c["plot"], arm=c["arm"], state="planned",
            reference_count=c["reference_count"], origin="reserve",
            source_directory=str(out / c["plot"] / c["arm"])) for c in matrix["cells"]],
        complete_detector_matrix=False, expansion_stopped=False,
        calibration_fitted=False, selected_arm="forestformer3d", inference_run=True)
    write_json(out / "run.json", receipt)
    refs = inputs.policy.calibration.read_csv(prepared / "contract/reference_apexes.csv")
    gpu = Path(read_json(root / "development_checkpoint_provenance_v2.json")["gpu_root"])
    runtime = Path(matrix["runtime_directory"])
    for cell, record in zip(matrix["cells"], receipt["cells"]):
        directory = Path(record["source_directory"])
        directory.mkdir(parents=True)
        record["state"] = "running"
        write_json(out / "run.json", receipt)
        print("Running reserve", cell["plot"], cell["arm"], flush=True)
        try:
            result = engine.run_cell(cell, directory, prepared / "inputs" / cell["plot"],
                                     gpu, runtime, refs)
            development.validate_success(dict(record, **result), cell, directory)
            record.update(result)
        except (Exception, KeyboardInterrupt) as error:
            record.update(state="failed", error=f"{type(error).__name__}: {error}")
            receipt["expansion_stopped"] = True
            print("Stopped:", record["error"], flush=True)
            break
        finally:
            write_json(out / "run.json", receipt)
    receipt["complete_detector_matrix"] = all(c["state"] in SUCCESS for c in receipt["cells"])
    receipt["output_sha256"] = output_hashes(out, matrix)
    write_json(out / "run.json", receipt)
    verify(root, prepared, out)
    return receipt["complete_detector_matrix"]


def verify(root, prepared, out):
    matrix = preflight(root, prepared, out)
    receipt = read_json(out / "run.json")
    if (receipt["schema_version"] != 1 or receipt["stage"] != "fgiemit_reserve_execution_v1" or
            receipt["development_root"] != str(root) or receipt["prepared_directory"] != str(prepared) or
            receipt["parent_sha256"] != parents(prepared) or receipt["code_sha256"] != code_hashes() or
            receipt["output_sha256"] != output_hashes(out, matrix) or
            receipt["calibration_fitted"] or receipt["selected_arm"] != "forestformer3d" or
            not receipt["inference_run"]):
        raise ValueError("Reserve execution scope, parents, code or outputs changed")
    validate_records(receipt, matrix, out)
    print("Reserve execution records and unchanged parents verified", flush=True)
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("root", "prepared", "out"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    paths = [getattr(args, n).resolve(strict=n != "out") for n in ("root", "prepared", "out")]
    if args.verify:
        verify(*paths)
    elif not run(*paths):
        raise SystemExit(1)
