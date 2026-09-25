#!/usr/bin/env python3
"""Summarize sealed development cells; incomplete support produces status only."""
import argparse
import csv
from pathlib import Path
import subprocess

import run_fgiemit_development as development

REPO = Path(__file__).resolve().parents[1]
FILES = ("scripts/summarize_fgiemit_development.py",
         "scripts/summarize_fgiemit_development.R",
         "scripts/fgiemit_development_summary_lib.R", "scripts/model_bench_lib.R")
COUNTS = ("n_pred", "n_ref", "TP", "FP", "FN")
MASK_FIELDS = ("sum_iou", "sum_maxiou", *(prefix + c for c in "ABCD"
               for prefix in ("n_", "tp_", "fn_", "sumiou_", "sumcov_")))
PRIMARY_FILES = ("cells.csv", "pooled.csv", "intervals.csv", "contrasts.csv",
                 "bootstrap_indices.csv", "analysis.json", "analysis.log")


def code_hashes():
    return {name: development.pilot.audit.file_hash(REPO / name) for name in FILES}


def output_hashes(out):
    return {p.name: development.pilot.audit.file_hash(p) for p in sorted(out.iterdir())
            if p.is_file() and p.name != "summary.json"}


def status_rows(receipt):
    rows = []
    for cell in receipt["cells"]:
        accepted = cell["state"] in development.SUCCESS
        resources = cell.get("resources", {})
        rows.append(dict(plot=cell["plot"], arm=cell["arm"], state=cell["state"],
            origin=cell["origin"], source_directory=cell["source_directory"],
            reference_count=cell["reference_count"],
            predictions=cell.get("predictions") if accepted else None,
            inference_wall_seconds=cell.get("inference_wall_seconds") if accepted else None,
            peak_host_rss_kib=resources.get("peak_host_rss_kib") if accepted else None,
            peak_cuda_allocated_bytes=resources.get("peak_cuda_allocated_bytes") if accepted else None,
            peak_cuda_reserved_bytes=resources.get("peak_cuda_reserved_bytes") if accepted else None,
            error=cell.get("error", "")))
    return rows


def metric_rows(receipt):
    if not receipt["complete_detector_matrix"]:
        raise ValueError("Primary pooling requires the complete detector matrix")
    rows = []
    for cell in receipt["cells"]:
        if cell["state"] not in development.SUCCESS:
            raise ValueError("Unsuccessful cells cannot supply primary metrics")
        base = dict(plot=cell["plot"], arm=cell["arm"], n_pred=cell["predictions"],
                    n_ref=cell["reference_count"])
        for detection in cell["metrics"]["detection"]:
            rows.append(dict(base, target="apex_" + detection["policy"],
                **{k: detection["apex_" + k] for k in ("TP", "FP", "FN")},
                **{k: None for k in MASK_FIELDS}))
        for mask in cell["metrics"]["mask"] or []:
            rows.append(dict(base, target="mask_iou_0.5",
                             **{k: mask[k] for k in (*COUNTS, *MASK_FIELDS)}))
    return rows


def write_csv(path, rows, fields=None):
    development.pilot.write_csv(path, rows, fields or list(rows[0]))


def summarize(root, run_dir, pilot_dir, runtime_dir, out):
    if out.parent != root or out.exists():
        raise ValueError("Use a new immediate summary directory; preserve earlier artifacts")
    run = development.verify(root, run_dir, pilot_dir, runtime_dir)
    out.mkdir()
    status = status_rows(run)
    write_csv(out / "status.csv", status)
    complete = run["complete_detector_matrix"]
    if complete:
        write_csv(out / "cells.csv", metric_rows(run),
                  ["plot", "arm", "target", *COUNTS, *MASK_FIELDS])
        with (out / "analysis.log").open("w") as log:
            subprocess.run(["Rscript", str(REPO / "scripts/summarize_fgiemit_development.R"),
                            str(out / "cells.csv"), str(out)], cwd=REPO,
                           stdout=log, stderr=subprocess.STDOUT, timeout=600, check=True)
    outputs = output_hashes(out)
    if set(outputs) != {"status.csv", *(PRIMARY_FILES if complete else ())}:
        raise ValueError("Analysis did not produce the required output set")
    receipt = dict(schema_version=1, stage="development_detector_summary",
        run_directory=str(run_dir), pilot_directory=str(pilot_dir), runtime_directory=str(runtime_dir),
        parent_sha256=development.pilot.audit.file_hash(run_dir / "run.json"),
        code_sha256=code_hashes(), output_sha256=outputs,
        primary_comparison_enabled=complete, calibration_fitted=False, reserve_evaluation_enabled=False,
        declared_cells=len(status), completed_cells=sum(c["state"] in development.SUCCESS for c in status),
        unavailable_cells=[{k: c[k] for k in ("plot", "arm", "state", "reference_count")}
                           for c in status if c["state"] not in development.SUCCESS],
        resamples=1000 if complete else 0, seed=20260923 if complete else None)
    development.pilot.write_json(out / "summary.json", receipt)
    return receipt


def verify(root, run_dir, pilot_dir, runtime_dir, out):
    run = development.verify(root, run_dir, pilot_dir, runtime_dir)
    receipt = development.read_json(out / "summary.json")
    complete = run["complete_detector_matrix"]
    if (receipt["schema_version"] != 1 or receipt["stage"] != "development_detector_summary" or
            out.parent != root or receipt["run_directory"] != str(run_dir) or
            receipt["pilot_directory"] != str(pilot_dir) or receipt["runtime_directory"] != str(runtime_dir) or
            receipt["primary_comparison_enabled"] != complete or receipt["calibration_fitted"] or
            receipt["reserve_evaluation_enabled"] or receipt["declared_cells"] != len(run["cells"]) or
            receipt["completed_cells"] != sum(c["state"] in development.SUCCESS for c in run["cells"]) or
            receipt["resamples"] != (1000 if complete else 0) or
            receipt["seed"] != (20260923 if complete else None)):
        raise ValueError("Changed analysis scope or completeness")
    unavailable = [{k: c[k] for k in ("plot", "arm", "state", "reference_count")}
                   for c in run["cells"] if c["state"] not in development.SUCCESS]
    if receipt["unavailable_cells"] != unavailable:
        raise ValueError("Changed unavailable-cell denominators")
    expected_files = {"status.csv", *(PRIMARY_FILES if complete else ())}
    if (set(receipt["output_sha256"]) != expected_files or
            receipt["output_sha256"] != output_hashes(out) or
            receipt["parent_sha256"] != development.pilot.audit.file_hash(run_dir / "run.json") or
            receipt["code_sha256"] != code_hashes()):
        raise ValueError("Changed analysis parent, code or outputs")
    with (out / "status.csv").open() as stream:
        actual = list(csv.DictReader(stream))
    expected = [{k: "" if v is None else str(v) for k, v in row.items()} for row in status_rows(run)]
    if actual != expected:
        raise ValueError("Status table differs from sealed cell states")
    print("Complete-support gate, analysis provenance and outputs verified", flush=True)
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("root", "run", "pilot", "runtime", "out"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    paths = (args.root.resolve(strict=True), args.run.resolve(strict=True),
             args.pilot.resolve(strict=True), args.runtime.resolve(strict=True), args.out.resolve())
    (verify if args.verify else summarize)(*paths)
