#!/usr/bin/env python3
"""Run the nine declared development pilot cells, stopping on the first failure."""
import argparse
import csv
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import uuid

import laspy
import numpy as np

import audit_fgiemit_development as audit
import declare_fgiemit_comparison as comparison
from fgiemit_comparison_lib import apex_profiles, PILOT, ARMS
from fgiemit_pilot_lib import aligned_labels, fixed_filter
import prepare_fgiemit_pilot_runtime as runtime

REPO = Path(__file__).resolve().parents[1]
FILES = ("scripts/run_fgiemit_pilot.py", "scripts/fgiemit_pilot_lib.py",
    "scripts/fgiemit_pilot_cell.R", "scripts/prepare_fgiemit_pilot_runtime.py",
    "gpu/run_fgiemit_segmentanytree.py", "gpu/fgiemit_sat_export.py",
    "gpu/sat_compat/usercustomize.py", "gpu/forestformer3d-sm120/ff3d_repo.patch")
APEX_FIELDS = ("instance", "policy", "points", "source_row", "x", "y", "z",
               "top_AGL_gap", "trimmed", "confidence")


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def code_hashes():
    return {name: audit.file_hash(REPO / name) for name in FILES}


def write_csv(path, rows, fields):
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader(); writer.writerows(rows)


def bounded(command, directory, env=None, container=None, timeout=3600):
    """A timeout stops the owned container as well as the local process group."""
    write_json(directory / "command.json", dict(argv=command, timeout_seconds=timeout))
    started = time.monotonic()
    with (directory / "inference.log").open("w") as log:
        proc = subprocess.Popen(command, cwd=REPO, env=env, stdout=log,
                                stderr=subprocess.STDOUT, start_new_session=True)
        try:
            status = proc.wait(timeout=timeout)
        except BaseException:
            if container:
                subprocess.run(["docker", "rm", "-f", container],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait()
            raise
    elapsed = time.monotonic() - started
    write_json(directory / "execution.json", dict(exit_code=status, wall_seconds=elapsed))
    if status:
        raise RuntimeError(f"Detector exited with status {status}; see inference.log")
    return elapsed


def docker_command(cell, directory, root, gpu):
    arm, plot = cell["arm"], cell["plot"]
    name = "fgiemit-pilot-" + uuid.uuid4().hex[:12]
    geometry = root / "development_inputs" / plot / "geometry.las"
    # Scoring references and receipts belong to the cell directory. Only a
    # fresh child workspace is visible to the model, even if references exist.
    model_io = directory / "model_io"
    model_io.mkdir()
    command = ["docker", "run", "--rm", "--name", name, "--network", "none", "--gpus", "all",
        "-v", f"{geometry}:/input/geometry.las:ro", "-v", f"{model_io}:/output",
        "-v", f"{REPO / 'gpu'}:/adapter:ro"]
    if arm == "segmentanytree":
        command += ["--shm-size=8g", "--ipc=host", "--entrypoint", "python3",
            cell["config"]["image"], "/adapter/run_fgiemit_segmentanytree.py",
            "/input/geometry.las", "/output/predictions.laz"]
    else:
        source = gpu / "store/forestformer3d/ForestFormer3D"
        model = model_io / "model"
        subprocess.run(["rsync", "-a", "--exclude=.git", "--exclude=data", "--exclude=work_dirs",
            "--exclude=__pycache__", str(source) + "/", str(model) + "/"], check=True)
        checkpoint = source / "work_dirs/clean_forestformer/epoch_3000_fix.pth"
        command += ["-v", f"{checkpoint}:/checkpoint/weights.pth:ro", "--entrypoint", "bash",
            cell["config"]["image"], "/adapter/forestformer3d-sm120/ff3d_entry.sh",
            "/input/geometry.las", "/output/predictions.laz", "/checkpoint/weights.pth",
            "/output/model", "/adapter/forestformer3d-sm120/ff3d_repo.patch",
            "/adapter/forestformer3d-sm120/ff3d_arm.py"]
    return command, name


def run_cell(cell, directory, root, gpu, runtime_dir, references):
    plot, arm = cell["plot"], cell["arm"]
    prepared = root / "development_inputs" / plot
    ref_rows = [r for r in references if r["plot"] == plot]
    write_csv(directory / "reference_apexes.csv", ref_rows, list(ref_rows[0]))
    output = directory / "prediction_apexes.csv"
    if arm == "chm_vwf":
        config = dict(cell["config"], frdens=cell["frdens"])
        write_json(directory / "config.json", config)
        command = ["/usr/bin/time", "-f", "%M", "-o", str(directory / "peak_rss_kib.txt"),
            "Rscript", str(REPO / "scripts/fgiemit_pilot_cell.R"), "chm",
            str(prepared / "normalized.laz"), str(directory / "config.json"), str(output)]
        elapsed = bounded(command, directory, env=runtime.environment(runtime_dir))
        preds = list(csv.DictReader(output.open()))
        if any(not all(np.isfinite(float(r[k])) for k in ("x", "y", "z")) for r in preds):
            raise ValueError("Nonfinite CHM detections")
        n_pred = len(preds)
        resources = dict(peak_host_rss_kib=int((directory / "peak_rss_kib.txt").read_text()),
                         peak_host_scope="R process maximum RSS")
    else:
        command, name = docker_command(cell, directory, root, gpu)
        elapsed = bounded(command, directory, container=name)
        source = laspy.read(prepared / "geometry.las")
        predicted = laspy.read(directory / "model_io/predictions.laz")
        labels, scores = aligned_labels(source, predicted, arm)
        labels, confidence = fixed_filter(labels, np.asarray(source.z), scores)
        np.savetxt(directory / "prediction_labels.csv", labels, fmt="%d",
                   header="pred_instance", comments="")
        normalized = laspy.read(prepared / "normalized.laz")
        if not np.array_equal(source.source_row, normalized.source_row):
            raise ValueError("Normalization row identity changed")
        raw = np.column_stack((source.x, source.y, source.z))
        agl = np.column_stack((normalized.x, normalized.y, normalized.z))
        profiles = apex_profiles(raw, agl, labels, source.source_row)
        for row in profiles:
            row["confidence"] = confidence[row["instance"]]
        write_csv(output, profiles, APEX_FIELDS)
        n_pred = len(confidence)
        resources = json.loads((directory / "model_io/predictions.laz.json").read_text())
        if arm == "forestformer3d":
            if len(resources) != 1 or resources[0]["source_rows"] != len(source.points):
                raise ValueError("FF3D did not run exactly one complete scene")
            resources = resources[0]
        resources["peak_host_scope"] = "native model process maximum RSS"
    score_command = ["Rscript", str(REPO / "scripts/fgiemit_pilot_cell.R"), "score",
        str(output), str(directory / "reference_apexes.csv"), arm,
        str(directory / "prediction_labels.csv"), str(prepared / "reference.laz"),
        str(directory / "metrics.json")]
    with (directory / "scoring.log").open("w") as log:
        subprocess.run(score_command, cwd=REPO, stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=600)
    return dict(state="successful_nonempty" if n_pred else "successful_empty",
        predictions=n_pred, inference_wall_seconds=elapsed, resources=resources,
        metrics=json.loads((directory / "metrics.json").read_text()))


def output_hashes(out):
    # Immutable acceptance outputs and logs; model scratch files are preserved
    # but are not accepted prediction artifacts.
    files = []
    for plot in PILOT:
        for arm in ARMS:
            directory = out / plot / arm
            if directory.exists():
                files.extend(p for p in directory.iterdir() if p.is_file())
                for name in ("model_io/predictions.laz", "model_io/predictions.laz.json",
                             "model_io/sat_native/native_0.npz"):
                    native = directory / name
                    if native.exists():
                        files.append(native)
    return {str(p.relative_to(out)): audit.file_hash(p) for p in sorted(files)}


def preflight(root, runtime_dir):
    comparison.verify(root, root / "development_comparison")
    runtime.verify(runtime_dir)
    plan = json.loads((root / "development_comparison/matrix.json").read_text())
    cells = [next(c for c in plan["cells"] if c["plot"] == p and c["arm"] == a)
             for p in PILOT for a in ARMS]
    if len(cells) != 9 or any(not c["pilot"] for c in cells):
        raise ValueError("Require exactly the frozen pilot cells")
    return cells


def run(root, out, runtime_dir):
    if out.parent != root or out.exists():
        raise ValueError("Use a new immediate pilot output directory; no retries or overwrites")
    cells = preflight(root, runtime_dir)
    gpu = Path(json.loads((root / "development_checkpoint_provenance_v2.json").read_text())["gpu_root"])
    parents = {str(p): audit.file_hash(p) for p in (
        root / "development_comparison/declaration.json", runtime_dir / "runtime.json")}
    _, protected = audit.workspace_inventory(root, out)
    out.mkdir()
    receipt = dict(schema_version=1, parent_sha256=parents, protected_sha256=protected,
        code_sha256=code_hashes(), cells=[dict(plot=c["plot"], arm=c["arm"], state="planned",
        reference_count=c["reference_count"]) for c in cells], runtime_directory=str(runtime_dir),
        calibration_fitted=False, reserve_evaluation_enabled=False, full_comparison=False)
    write_json(out / "pilot.json", receipt)
    refs = list(csv.DictReader((root / "development_comparison/reference_apexes.csv").open()))
    for index, cell in enumerate(cells):
        directory = out / cell["plot"] / cell["arm"]
        directory.mkdir(parents=True)
        record = receipt["cells"][index]
        record["state"] = "running"
        write_json(out / "pilot.json", receipt)
        print("Running", cell["plot"], cell["arm"], flush=True)
        try:
            record.update(run_cell(cell, directory, root, gpu, runtime_dir, refs))
        except Exception as error:
            record.update(state="failed", error=f"{type(error).__name__}: {error}")
            receipt["expansion_stopped"] = True
            print("Stopped:", record["error"], flush=True)
            break
        finally:
            write_json(out / "pilot.json", receipt)
    receipt["output_sha256"] = output_hashes(out)
    receipt["complete_pilot"] = all(c["state"].startswith("successful_") for c in receipt["cells"])
    write_json(out / "pilot.json", receipt)
    verify(root, out, runtime_dir)


def verify(root, out, runtime_dir):
    cells = preflight(root, runtime_dir)
    receipt = json.loads((out / "pilot.json").read_text())
    if (receipt["schema_version"] != 1 or receipt["calibration_fitted"] or
            receipt["reserve_evaluation_enabled"] or receipt["full_comparison"] or
            receipt["runtime_directory"] != str(runtime_dir) or out.parent != root or
            [(c["plot"], c["arm"]) for c in receipt["cells"]] !=
            [(c["plot"], c["arm"]) for c in cells]):
        raise ValueError("Invalid pilot scope")
    if receipt["code_sha256"] != code_hashes() or receipt["output_sha256"] != output_hashes(out):
        raise ValueError("Pilot code or accepted output changed")
    stopped = False
    for expected_cell, actual in zip(cells, receipt["cells"]):
        state = actual["state"]
        if (actual["reference_count"] != expected_cell["reference_count"] or
                state not in ("planned", "failed", "successful_empty", "successful_nonempty") or
                (stopped and state != "planned")):
            raise ValueError("Invalid pilot state, denominator or expansion after failure")
        stopped = stopped or state in ("failed", "planned")
    if receipt["complete_pilot"] != all(c["state"].startswith("successful_") for c in receipt["cells"]):
        raise ValueError("Pilot completeness differs from cell states")
    for name, expected in receipt["parent_sha256"].items():
        if audit.file_hash(Path(name)) != expected:
            raise ValueError("Pilot parent changed")
    for name, expected in receipt["protected_sha256"].items():
        if audit.file_hash(root / name) != expected:
            raise ValueError("Protected prior artifact changed")
    print("Pilot receipts, accepted outputs and protected artifacts verified", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    root, out, runtime_dir = args.root.resolve(strict=True), args.out.resolve(), args.runtime.resolve(strict=True)
    (verify if args.verify else run)(root, out, runtime_dir)
