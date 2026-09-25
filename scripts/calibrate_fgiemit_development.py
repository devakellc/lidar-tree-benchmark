#!/usr/bin/env python3
"""Calibrate the complete frozen development matrix with whole-plot validation."""
import argparse
import csv
from pathlib import Path
import subprocess

import summarize_fgiemit_development as summary

development = summary.development
REPO = Path(__file__).resolve().parents[1]
FEATURES = dict(chm_vwf="AGL_height_proxy", segmentanytree="retained_instance_point_count",
                forestformer3d="mean_native_ff3d_score")
FILES = ("scripts/calibrate_fgiemit_development.py", "scripts/calibrate_fgiemit_development.R",
         "scripts/fgiemit_calibration_lib.R", "scripts/model_bench_lib.R",
         "scripts/transfer_audit_lib.R", "scripts/fgiemit_development_summary_lib.R",
         "scripts/repo_paths.R")
OUTPUTS = {"cells.csv", "folds.csv", "predictions.csv", "status.csv", "knots.csv",
           "pooled.csv", "reliability.csv", "intervals.csv", "bootstrap_indices.csv",
           "analysis.json", "analysis.log"}


def code_hashes():
    return {p: development.pilot.audit.file_hash(REPO / p) for p in FILES}


def output_hashes(out):
    return {p.name: development.pilot.audit.file_hash(p) for p in sorted(out.iterdir())
            if p.is_file() and p.name != "calibration.json"}


def fold_rows(matrix):
    expected = []
    for plot in sorted(development.DEVELOPMENT):
        for arm in development.ARMS:
            for target in ("apex_max_agl",) + (() if arm == "chm_vwf" else ("mask_iou_0.5",)):
                expected.append(dict(fold="leave_" + plot + "_out", validation_plot=plot,
                    calibration_plots=sorted(development.DEVELOPMENT - {plot}), arm=arm,
                    target=target, confidence_feature=FEATURES[arm], state="planned"))
    if matrix["calibration_cells"] != expected:
        raise ValueError("Require the exact fifty frozen whole-plot calibration cells")
    return [dict(fold=c["fold"], plot=c["validation_plot"], arm=c["arm"], target=c["target"],
                 calibration_plots=";".join(c["calibration_plots"]),
                 confidence_feature=c["confidence_feature"]) for c in expected]


def cell_rows(root, run):
    sources = {(c["plot"], c["arm"]): c for c in run["cells"]}
    rows = []
    for row in summary.metric_rows(run):
        if row["target"] not in ("apex_max_agl", "mask_iou_0.5"):
            continue
        cell = sources[row["plot"], row["arm"]]
        source = (root / cell["source_directory"]).resolve(strict=True)
        if not source.is_relative_to(root):
            raise ValueError("Cell source directory escapes the sealed data root")
        rows.append(dict({k: row[k] for k in ("plot", "arm", "target", *summary.COUNTS)},
            source_directory=str(source),
            reference_path=str(root / "development_inputs" / row["plot"] / "reference.laz")))
    return rows


def preflight(root, run_dir, pilot_dir, runtime_dir, summary_dir):
    parent = summary.verify(root, run_dir, pilot_dir, runtime_dir, summary_dir)
    if not parent["primary_comparison_enabled"]:
        raise ValueError("Calibration requires the complete detector comparison")
    run = development.read_json(run_dir / "run.json")
    matrix = development.read_json(root / "development_comparison/matrix.json")
    return cell_rows(root, run), fold_rows(matrix)


def parent_hashes(root, run_dir, summary_dir):
    return {str(p.relative_to(root)): development.pilot.audit.file_hash(p) for p in
            (run_dir / "run.json", summary_dir / "summary.json",
             root / "development_comparison/matrix.json")}


def read_csv(path):
    with path.open() as stream:
        return list(csv.DictReader(stream))


def check_outputs(out, cells, folds):
    if set(output_hashes(out)) != OUTPUTS:
        raise ValueError("Calibration did not produce the required output set")
    for name, rows in (("cells", cells), ("folds", folds)):
        expected = [{k: str(v) for k, v in row.items()} for row in rows]
        if read_csv(out / (name + ".csv")) != expected:
            raise ValueError("Changed calibration input table")
    status = read_csv(out / "status.csv")
    if len(status) != 50 or any(any(row[k] != str(fold[k]) for k in fold)
                                for row, fold in zip(status, folds)):
        raise ValueError("Calibration status differs from declared folds")
    by_key = {(c["plot"], c["arm"], c["target"]): c for c in cells}
    for row in status:
        cell = by_key[row["plot"], row["arm"], row["target"]]
        n = int(row["n_pred"])
        if (n != cell["n_pred"] or int(row["TP"]) != cell["TP"] or
                row["state"] != ("successful_nonempty" if n else "successful_empty") or
                row["fit_state"] not in ("fitted", "unavailable") or
                min(int(row["calibrated"]), int(row["unavailable"])) < 0 or
                int(row["calibrated"]) + int(row["unavailable"]) != n):
            raise ValueError("Calibration coverage or baseline counts changed")
    analysis = development.read_json(out / "analysis.json")
    expected = dict(cells=50, fitted_cells=sum(r["fit_state"] == "fitted" for r in status),
        unavailable_fit_cells=sum(r["fit_state"] == "unavailable" for r in status),
        validation_predictions=sum(c["n_pred"] for c in cells),
        calibrated_predictions=sum(int(r["calibrated"]) for r in status),
        resamples=1000, seed=20260923, refit_in_bootstrap=False, reserve_evaluation_enabled=False)
    if any(analysis[k] != v for k, v in expected.items()):
        raise ValueError("Calibration analysis scope or counts changed")
    return analysis


def calibrate(root, run_dir, pilot_dir, runtime_dir, summary_dir, out):
    if out.parent != root or out.exists():
        raise ValueError("Use a new immediate calibration directory; preserve earlier artifacts")
    cells, folds = preflight(root, run_dir, pilot_dir, runtime_dir, summary_dir)
    out.mkdir()
    for name, rows in (("cells", cells), ("folds", folds)):
        summary.write_csv(out / (name + ".csv"), rows)
    with (out / "analysis.log").open("w") as log:
        subprocess.run(["Rscript", str(REPO / "scripts/calibrate_fgiemit_development.R"), str(out)],
                       cwd=REPO, stdout=log, stderr=subprocess.STDOUT, timeout=3600, check=True)
    analysis = check_outputs(out, cells, folds)
    receipt = dict(schema_version=1, stage="development_calibration",
        run_directory=str(run_dir), pilot_directory=str(pilot_dir), runtime_directory=str(runtime_dir),
        summary_directory=str(summary_dir), parent_sha256=parent_hashes(root, run_dir, summary_dir),
        code_sha256=code_hashes(), output_sha256=output_hashes(out),
        complete_calibration_matrix=True, calibration_fitted=analysis["fitted_cells"] > 0,
        declared_cells=50, fitted_cells=analysis["fitted_cells"],
        reserve_evaluation_enabled=False, threshold_selected=False, fusion_enabled=False,
        deployment_lookup_exported=False)
    development.pilot.write_json(out / "calibration.json", receipt)
    print("Completed fifty whole-plot calibration cells; reserve remains closed", flush=True)
    return receipt


def verify(root, run_dir, pilot_dir, runtime_dir, summary_dir, out):
    cells, folds = preflight(root, run_dir, pilot_dir, runtime_dir, summary_dir)
    receipt = development.read_json(out / "calibration.json")
    analysis = check_outputs(out, cells, folds)
    expected = dict(schema_version=1, stage="development_calibration",
        run_directory=str(run_dir), pilot_directory=str(pilot_dir), runtime_directory=str(runtime_dir),
        summary_directory=str(summary_dir), parent_sha256=parent_hashes(root, run_dir, summary_dir),
        code_sha256=code_hashes(), output_sha256=output_hashes(out),
        complete_calibration_matrix=True, calibration_fitted=analysis["fitted_cells"] > 0,
        declared_cells=50, fitted_cells=analysis["fitted_cells"],
        reserve_evaluation_enabled=False, threshold_selected=False, fusion_enabled=False,
        deployment_lookup_exported=False)
    if out.parent != root or receipt != expected:
        raise ValueError("Changed calibration scope, parent, code or outputs")
    print("Calibration folds, baseline counts, coverage and provenance verified", flush=True)
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("root", "run", "pilot", "runtime", "summary", "out"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    paths = tuple(getattr(args, name).resolve(strict=name != "out") for name in
                  ("root", "run", "pilot", "runtime", "summary", "out"))
    (verify if args.verify else calibrate)(*paths)
