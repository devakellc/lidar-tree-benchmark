"""Explicit-input reserve cell execution; unchanged admitted algorithms and exports."""
import csv
import json
from pathlib import Path
import subprocess
import uuid

import laspy
import numpy as np

from run_fgiemit_pilot import bounded, write_json, write_csv, APEX_FIELDS
from fgiemit_pilot_lib import aligned_labels, fixed_filter
from fgiemit_comparison_lib import apex_profiles
import prepare_fgiemit_pilot_runtime as runtime

REPO = Path(__file__).resolve().parents[1]


def docker_command(cell, directory, prepared, gpu):
    arm, plot = cell["arm"], cell["plot"]
    name = "fgiemit-reserve-" + uuid.uuid4().hex[:12]
    geometry = prepared / "geometry.las"
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


def run_cell(cell, directory, prepared, gpu, runtime_dir, references):
    plot, arm = cell["plot"], cell["arm"]
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
        command, name = docker_command(cell, directory, prepared, gpu)
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

