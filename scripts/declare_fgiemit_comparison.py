#!/usr/bin/env python3
"""Seal planned development cells and height references without inference."""
import argparse
import csv
import json
from pathlib import Path
import subprocess

import laspy
import numpy as np
import yaml

import audit_fgiemit_development as audit
import audit_fgiemit_checkpoints as checkpoints
import prepare_fgiemit_development as inputs
from fgiemit_comparison_lib import apex_profiles, build_matrix, DEVELOPMENT

REPO = Path(__file__).resolve().parents[1]
CODE_FILES = ("scripts/declare_fgiemit_comparison.py", "scripts/fgiemit_comparison_lib.py",
    "docs/fgiemit-comparison-protocol.md", "scripts/sweep_lib.R",
    "scripts/external_fgiemit_lib.R", "scripts/transfer_audit_lib.R", "scripts/model_bench_lib.R",
    "gpu/run_segmentanytree.py", "gpu/forestformer3d-sm120/ff3d_arm.py",
    "gpu/forestformer3d-sm120/ff3d_export.py", "gpu/forestformer3d-sm120/ff3d_entry.sh",
    "gpu/evaluate_fgiemit.py")
PARENTS = ("development_declaration/declaration.json", "development_declaration/folds.json",
           "development_inputs/manifest.json", "development_checkpoint_provenance_v2.json")


def preflight(root):
    inputs.verify(root, root / "development_inputs")
    prepared = json.loads((root / "development_inputs/manifest.json").read_text())
    provenance = json.loads((root / PARENTS[-1]).read_text())
    if provenance != checkpoints.collect(Path(provenance["gpu_root"])):
        raise ValueError("Installed checkpoint provenance changed")
    folds = json.loads((root / PARENTS[1]).read_text())
    return prepared, build_matrix(prepared, provenance, folds)


def code_hashes():
    return {name: audit.file_hash(REPO / name) for name in CODE_FILES}


def r_environment():
    code = '''p <- utils::packageDescription("lasR")
s <- try(lasR::local_maximum_raster(lasR::rasterize(.25, "max"),
    function(h) pmin(pmax(.1*h+3,3),5)), silent=TRUE)
if (inherits(s, "try-error")) stop("Missing lasR variable-window capability")
v <- vapply(c("lasR", "lidR", "terra", "sf", "data.table"),
            function(x) as.character(utils::packageVersion(x)), character(1))
cat(jsonlite::toJSON(list(versions=as.list(v), lasR_ref=p$RemoteRef,
    lasR_commit=p$RemoteSha, lasR_path=find.package("lasR"),
    variable_window_constructor=TRUE), auto_unbox=TRUE, null="null"))'''
    runtime = json.loads(subprocess.check_output(["Rscript", "-e", code], text=True, timeout=60))
    package = Path(runtime["lasR_path"])
    files = [package / "DESCRIPTION", *sorted((package / "R").glob("lasR.*")),
             *sorted((package / "libs").rglob("*.so"))]
    runtime["lasR_installed_sha256"] = {str(p.relative_to(package)): audit.file_hash(p) for p in files}
    runtime["lasR_required_lineage"] = "r-lidar/lasR@pre-devel"
    runtime["lasR_lineage_verified"] = runtime["lasR_ref"] == "pre-devel" and bool(runtime["lasR_commit"])
    return runtime


def reference_rows(directory, plot, metadata):
    if plot not in DEVELOPMENT:
        raise ValueError("Reference construction is restricted to development plots")
    reference = laspy.read(directory / plot / "reference.laz")
    normalized = laspy.read(directory / plot / "normalized.laz")
    if not np.array_equal(reference.source_row, normalized.source_row):
        raise ValueError("Prepared reference and normalization row IDs disagree")
    raw = np.column_stack((reference.x, reference.y, reference.z))
    agl = np.column_stack((normalized.x, normalized.y, normalized.z))
    profiles = apex_profiles(raw, agl, reference.tree_index, reference.source_row)
    expected = {int(tree) for tree in metadata["trees"]}
    if {r["instance"] for r in profiles} != expected or len(profiles) != 3 * len(expected):
        raise ValueError("Reference population differs from published metadata")
    for row in profiles:
        row.update(plot=plot, coordinate_frame=f"FGI-EMIT/19351234/plot_{plot}",
                   category=metadata["trees"][row["instance"]]["c"])
    return profiles


def write_csv(path, rows):
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def declare(root, out):
    if out.parent != root or out.exists():
        raise ValueError("Use a new immediate output directory; preserve existing declarations")
    prepared, plan = preflight(root)
    runtime = r_environment()
    code = code_hashes()
    parents = {p: audit.file_hash(root / p) for p in PARENTS}
    _, protected = audit.workspace_inventory(root, out)
    metadata = yaml.safe_load((root / "source/plot_data.yaml").read_text())
    rows = []
    for plot in sorted(DEVELOPMENT):
        rows.extend(reference_rows(root / "development_inputs", plot, metadata[int(plot)]))
        print(f"Constructed three reference profiles: {plot}", flush=True)
    if len(rows) != 3 * sum(r["reference_trees"] for r in prepared["results"]):
        raise ValueError("Reference counts changed")
    # No model output or metric is read. Check the prepared assets again after
    # the reference pass before publishing its declaration.
    inputs.verify(root, root / "development_inputs")
    for path, expected in {**parents, **protected}.items():
        if audit.file_hash(root / path) != expected:
            raise ValueError(f"Prior input/artifact changed: {path}")
    if code != code_hashes():
        raise ValueError("Contract code/protocol changed during declaration")
    out.mkdir()
    (out / "matrix.json").write_text(json.dumps(plan, indent=2) + "\n")
    write_csv(out / "cells.csv", [{k: v for k, v in c.items() if k != "config"} for c in plan["cells"]])
    write_csv(out / "reference_apexes.csv", rows)
    outputs = {name: audit.file_hash(out / name)
               for name in ("matrix.json", "cells.csv", "reference_apexes.csv")}
    declaration = dict(schema_version=1, protocol="fgiemit-development-comparison-v1",
        output_directory=out.name, parent_sha256=parents, protected_sha256=protected,
        code_sha256=code, output_sha256=outputs, R_environment=runtime,
        references=len(rows) // 3, profiles=3, planned_inference_cells=len(plan["cells"]),
        planned_calibration_cells=len(plan["calibration_cells"]),
        inference_run=False, calibration_fitted=False, reserve_evaluation_enabled=False)
    (out / "declaration.json").write_text(json.dumps(declaration, indent=2) + "\n")
    print(f"Sealed {len(plan['cells'])} planned detector cells, 50 calibration cells and {len(rows)//3} references")


def verify(root, out):
    declaration = json.loads((out / "declaration.json").read_text())
    if (declaration["schema_version"] != 1 or declaration["output_directory"] != out.name or
            out.parent != root or declaration["inference_run"] or declaration["calibration_fitted"] or
            declaration["reserve_evaluation_enabled"]):
        raise ValueError("Invalid unexecuted comparison declaration")
    _, plan = preflight(root)
    if code_hashes() != declaration["code_sha256"] or r_environment() != declaration["R_environment"]:
        raise ValueError("Contract code/protocol or R environment changed")
    for group in ("parent_sha256", "protected_sha256"):
        for path, expected in declaration[group].items():
            resolved = (root / path).resolve()
            if not resolved.is_relative_to(root) or audit.file_hash(resolved) != expected:
                raise ValueError(f"Prior input/artifact changed: {path}")
    for name, expected in declaration["output_sha256"].items():
        if audit.file_hash(out / name) != expected:
            raise ValueError(f"Comparison output changed: {name}")
    if json.loads((out / "matrix.json").read_text()) != plan:
        raise ValueError("Planned matrix differs from the fixed contract")
    print("Comparison parents, protected artifacts, matrix and reference outputs verified")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    root, out = args.root.resolve(strict=True), args.out.resolve()
    (verify if args.verify else declare)(root, out)


if __name__ == "__main__":
    main()
