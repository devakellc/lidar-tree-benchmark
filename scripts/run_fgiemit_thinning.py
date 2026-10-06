"""Run and score the FGI-EMIT thinning cells (docs/fgiemit-thinning-protocol.md).

Every cell runs once through the admitted explicit-input runner
(fgiemit_reserve_cell_v2.run_cell): the development matrix's images,
checkpoints and admitted post-processing (the fixed filter). The learned
arms are then re-scored from the same saved predictions with the NEON
reduction, which keeps every instance whose top is at least 2 m above ground
(prediction_*_neon.csv, metrics_neon.json). CHM-VWF follows the NEON paper
rule (0.25 m at 8 or more first returns per m², else 0.5 m). A cell with a
directory but no metrics is a failed attempt: the run stops rather than
retrying it, except that a learned cell whose inference finished (exit 0,
predictions and their filtered labels saved) and whose scoring failed is
re-scored from those saved files without running the model again
(rescore_cell). MODE=native writes the NEON reduction for the development
matrix's native predictions, without inference.

    python scripts/run_fgiemit_thinning.py <fgiemit root> <selection dir> <out dir>
        <runtime dir> [arms] [MODE=thin|native]
"""
import csv
import json
import subprocess
import sys
from pathlib import Path

import laspy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fgiemit_reserve_cell_v2 as cells  # noqa: E402
from fgiemit_comparison_lib import apex_profiles  # noqa: E402
from fgiemit_pilot_lib import aligned_labels  # noqa: E402
from run_fgiemit_pilot import APEX_FIELDS, write_csv, write_json  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
DEV = ("1001", "1005", "1009", "1013", "1019", "1020", "1022", "1024", "1027", "1031")
PILOT = ("1001", "1019", "1027")
ARMS = ("chm_vwf", "segmentanytree", "forestformer3d")


def neon_reduction(prepared, directory, arm, references):
    """Re-score saved predictions keeping every instance topped at >= 2 m AGL."""
    source = laspy.read(prepared / "geometry.las")
    predicted = laspy.read(directory / "model_io/predictions.laz")
    labels, _ = aligned_labels(source, predicted, arm)
    labels = np.asarray(labels).astype(np.int64)
    normalized = laspy.read(prepared / "normalized.laz")
    if not np.array_equal(source.source_row, normalized.source_row):
        raise ValueError("Normalization row identity changed")
    agl = np.asarray(normalized.z)
    keep = np.zeros(labels.shape, dtype=np.int64)
    for k in np.unique(labels[labels > 0]):
        idx = np.flatnonzero(labels == k)
        if agl[idx].max() >= 2.0:
            keep[idx] = k
    np.savetxt(directory / "prediction_labels_neon.csv", keep, fmt="%d", header="pred_instance",
               comments="")
    raw = np.column_stack((source.x, source.y, source.z))
    agl_xyz = np.column_stack((normalized.x, normalized.y, normalized.z))
    profiles = apex_profiles(raw, agl_xyz, keep, source.source_row)
    for row in profiles:
        row["confidence"] = row["points"]
    write_csv(directory / "prediction_apexes_neon.csv", profiles, APEX_FIELDS)
    ref_rows = [r for r in references if r["plot"] == directory.parent.parent.name]
    write_csv(directory / "reference_apexes.csv", ref_rows, list(ref_rows[0]))
    command = ["Rscript", str(REPO / "scripts/fgiemit_pilot_cell.R"), "score",
               str(directory / "prediction_apexes_neon.csv"), str(directory / "reference_apexes.csv"),
               arm, str(directory / "prediction_labels_neon.csv"), str(prepared / "reference.laz"),
               str(directory / "metrics_neon.json")]
    with (directory / "scoring_neon.log").open("w") as log:
        subprocess.run(command, cwd=REPO, stdout=log, stderr=subprocess.STDOUT, check=True,
                       timeout=600)


def rescore_cell(cell, directory, prepared, references):
    """Score a learned cell's saved inference again, without re-running the model.

    The cell runner's tail (fgiemit_reserve_cell_v2.run_cell), from the
    labels and apex profiles it had already written before scoring failed.
    """
    execution = json.loads((directory / "execution.json").read_text())
    if execution["exit_code"] != 0:
        raise RuntimeError(f"Inference did not finish, not retried: {directory}")
    output = directory / "prediction_apexes.csv"
    labels = np.loadtxt(directory / "prediction_labels.csv", skiprows=1, dtype=np.int64)
    n_pred = len({r["instance"] for r in csv.DictReader(output.open())})
    if n_pred != len(np.unique(labels[labels > 0])):
        raise ValueError(f"Saved labels and apex profiles disagree: {directory}")
    ref_rows = [r for r in references if r["plot"] == cell["plot"]]
    write_csv(directory / "reference_apexes.csv", ref_rows, list(ref_rows[0]))
    resources = json.loads((directory / "model_io/predictions.laz.json").read_text())
    if cell["arm"] == "forestformer3d":
        resources = resources[0]
    resources["peak_host_scope"] = "native model process maximum RSS"
    command = ["Rscript", str(REPO / "scripts/fgiemit_pilot_cell.R"), "score", str(output),
               str(directory / "reference_apexes.csv"), cell["arm"],
               str(directory / "prediction_labels.csv"), str(prepared / "reference.laz"),
               str(directory / "metrics.json")]
    with (directory / "scoring.log").open("w") as log:
        subprocess.run(command, cwd=REPO, stdout=log, stderr=subprocess.STDOUT, check=True,
                       timeout=600)
    return dict(state="successful_nonempty" if n_pred else "successful_empty",
                predictions=n_pred, inference_wall_seconds=execution["wall_seconds"],
                resources=resources, rescored=True,
                metrics=json.loads((directory / "metrics.json").read_text()))


def configs(root):
    matrix = json.loads((root / "development_comparison/matrix.json").read_text())
    return {c["arm"]: c["config"] for c in matrix["cells"] if c["plot"] == "1001"}


def main(root, selection, out, runtime_dir, arms=",".join(ARMS), mode="MODE=thin"):
    root, selection, out = Path(root).resolve(), Path(selection).resolve(), Path(out).resolve()
    runtime_dir = Path(runtime_dir).resolve()
    if root in out.parents:
        raise ValueError("Outputs must be outside the FGI-EMIT root")
    arms = [a for a in arms.split(",") if a in ARMS]
    references = list(csv.DictReader((root / "development_comparison/reference_apexes.csv").open()))
    if mode == "MODE=native":
        for plot in DEV:
            run = "development_pilot_v3" if plot in PILOT else "development_detector_run"
            for arm in [a for a in arms if a != "chm_vwf"]:
                directory = out / "native" / plot / "native" / arm
                directory.mkdir(parents=True, exist_ok=True)
                saved = root / run / plot / arm / "model_io/predictions.laz"
                (directory / "model_io").mkdir(exist_ok=True)
                link = directory / "model_io/predictions.laz"
                if not link.exists():
                    link.symlink_to(saved)
                neon_reduction(root / "development_inputs" / plot, directory, arm, references)
                print(plot, arm, "native NEON reduction")
        return
    densities = {(r["plot"], r["label"]): float(r["frdens"])
                 for r in csv.DictReader((selection / "thinning_densities.csv").open())}
    config = configs(root)
    labels = sorted({k[1] for k in densities if k[1] != "native"},
                    key=lambda s: -float(s.split("_")[1]))
    for label in labels:
        for plot in DEV:
            prepared = selection / plot / label
            if not (prepared / "receipt.json").exists():
                continue
            for arm in arms:
                directory = out / "run" / plot / label / arm
                if (directory / "result.json").exists():
                    continue
                frdens = densities[(plot, label)]
                cfg = dict(config[arm])
                if arm == "chm_vwf":
                    cfg["resolution_m"] = 0.25 if frdens >= 8 else 0.5
                cell = dict(plot=plot, arm=arm, config=cfg, frdens=frdens)
                if directory.exists():
                    saved = [directory / f for f in ("execution.json", "prediction_labels.csv",
                                                     "prediction_apexes.csv")]
                    if arm == "chm_vwf" or not all(f.exists() for f in saved):
                        raise RuntimeError(f"Failed earlier attempt, not retried: {directory}")
                    result = rescore_cell(cell, directory, prepared, references)
                else:
                    directory.mkdir(parents=True)
                    result = cells.run_cell(cell, directory, prepared, REPO / "gpu", runtime_dir,
                                            references)
                if arm != "chm_vwf":
                    neon_reduction(prepared, directory, arm, references)
                write_json(directory / "result.json", result)
                print(plot, label, arm, result["state"], round(result["inference_wall_seconds"], 1))


if __name__ == "__main__":
    main(*sys.argv[1:])
