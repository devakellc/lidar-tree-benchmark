#!/usr/bin/env python3
"""Validate declared development points and prepare label-free local inputs."""
import argparse
import csv
import json
from pathlib import Path
import subprocess
import sys
import time

import laspy
import numpy as np
from scipy.spatial import ConvexHull, Delaunay
import scipy
import yaml

import audit_fgiemit_development as audit

REPO = Path(__file__).resolve().parents[1]
CODE_FILES = ("scripts/prepare_fgiemit_development.py",
              "scripts/normalize_fgiemit_development.R",
              "docs/fgiemit-input-validation-protocol.md")
DEVELOPMENT = {"1001", "1005", "1009", "1013", "1019", "1020", "1022", "1024", "1027", "1031"}


def check_declaration(root, directory):
    declaration = json.loads((directory / "declaration.json").read_text())
    if (directory.parent != root or directory.name != declaration["output_directory"] or
            set(declaration["development"]) != DEVELOPMENT or
            len(declaration["development"]) != len(DEVELOPMENT) or
            set(declaration["evaluation_reserve"]) != audit.RESERVED_PLOTS or
            set(declaration["historical_test"]) != audit.TEST_PLOTS or
            declaration["rungs"] != ["native"] or declaration["evaluation_admitted"]):
        raise ValueError("Incompatible development declaration")
    audit.verify(declaration, root)
    for name, expected in declaration["output_sha256"].items():
        if audit.file_hash(directory / name) != expected:
            raise ValueError("Declared folds or inventory changed")
    return declaration


def select_plots(plots):
    selected = sorted(DEVELOPMENT) if plots is None else plots.split(",")
    if not selected or len(set(selected)) != len(selected) or not set(selected) <= DEVELOPMENT:
        raise ValueError("Only unique declared development plots may be opened")
    return selected


def validate_points(cloud, metadata):
    dims = set(cloud.point_format.dimension_names)
    if not {"tree_index", "edge", "dead", "user_data"} <= dims:
        raise ValueError("Missing reference annotation fields")
    xyz = np.column_stack((cloud.x, cloud.y, cloud.z))
    if not np.isfinite(xyz).all() or cloud.header.parse_crs() is not None:
        raise ValueError("Expected finite plot-local coordinates without an EPSG")
    semantic = np.asarray(cloud.classification)
    labels = np.asarray(cloud.tree_index)
    rn, nr = np.asarray(cloud.return_number), np.asarray(cloud.number_of_returns)
    if np.any((rn < 1) | (nr < rn) | (nr > 15)):
        raise ValueError("Invalid original return numbers")
    if not np.isin(semantic, np.arange(6)).all():
        raise ValueError("Unknown semantic annotation")
    if not np.all(np.isfinite(labels) & (labels >= 0) & (labels == np.floor(labels))):
        raise ValueError("Invalid instance IDs")
    if np.any((semantic == 1) != (labels > 0)):
        raise ValueError("Semantic trees and instance IDs disagree")
    if not all(np.isin(cloud[name], [0, 1]).all() for name in ("edge", "dead")):
        raise ValueError("Invalid edge/dead flags")
    trees = {int(k): v for k, v in metadata["trees"].items()}
    if set(np.unique(labels[labels > 0])) != set(trees) or len(trees) != metadata["n_trees"]["all"]:
        raise ValueError("Reference instance IDs disagree with metadata")
    for category in "ABCD":
        if sum(t["c"] == category for t in trees.values()) != metadata["n_trees"][category]:
            raise ValueError("Reference categories disagree with metadata")
    for tree in trees.values():
        if tree["c"] not in "ABCD" or not np.isfinite([tree[k] for k in ("x", "y", "h")]).all():
            raise ValueError("Invalid tree metadata")
    keep = semantic != 5
    rows = np.flatnonzero(keep).astype("uint32")
    xy = xyz[keep, :2]
    hull = ConvexHull(xy)
    area = float(hull.volume)
    if not np.isfinite(area) or area <= 0:
        raise ValueError("Invalid retained point footprint")
    first = int(np.count_nonzero(rn[keep] == 1))
    counts = np.bincount(rn, minlength=16)[1:16]
    if not np.array_equal(counts, cloud.header.number_of_points_by_return):
        raise ValueError("Original return counts disagree with header")
    info = dict(source_points=len(cloud.points), retained_points=len(rows),
                excluded_class5=int(np.count_nonzero(~keep)), reference_trees=len(trees),
                semantic_counts={str(i): int(np.count_nonzero(semantic == i)) for i in range(6)},
                first_returns=first, footprint_area_m2=area,
                footprint_xy=xy[hull.vertices].tolist(), published_area_m2=metadata["area"] * 10000,
                frdens=first / area, pdens=len(rows) / area,
                density_basis="original_retained_returns_over_retained_XY_convex_hull",
                raw_z_range=[float(xyz[:, 2].min()), float(xyz[:, 2].max())],
                declared_crs=None, independent_AGL_validated=False)
    return keep, rows, info


def verify_geometry(source, prepared, rows):
    if len(prepared.points) != len(rows) or not np.array_equal(prepared.source_row, rows):
        raise ValueError("Export changed source row identity")
    for name in ("X", "Y", "Z", "return_number", "number_of_returns"):
        if not np.array_equal(source[name][rows], prepared[name]):
            raise ValueError(f"Export changed source field: {name}")
    for name in ("scales", "offsets"):
        if not np.array_equal(getattr(source.header, name), getattr(prepared.header, name)):
            raise ValueError(f"Export changed coordinate {name}")


def export_inputs(source, keep, rows, directory):
    header = laspy.LasHeader(point_format=7, version="1.4")
    header.scales = source.header.scales.copy()
    header.offsets = source.header.offsets.copy()
    header.add_extra_dim(laspy.ExtraBytesParams(name="source_row", type="uint32"))
    model = laspy.LasData(header)
    for name in ("X", "Y", "Z", "return_number", "number_of_returns"):
        model[name] = np.asarray(source[name])[keep]
    model.classification = np.ones(len(rows), dtype="uint8")
    model.source_row = rows
    model.write(directory / "geometry.las")
    verify_geometry(source, laspy.read(directory / "geometry.las"), rows)
    reference = laspy.LasData(source.header.copy(), source.points[keep].copy())
    reference.remove_extra_dims([n for n in reference.point_format.extra_dimension_names
                                 if n not in ("tree_index", "edge", "dead")])
    reference.add_extra_dim(laspy.ExtraBytesParams(name="source_row", type="uint32"))
    reference.source_row = rows
    reference.write(directory / "reference.laz")
    saved = laspy.read(directory / "reference.laz")
    verify_geometry(source, saved, rows)
    for name in ("classification", "tree_index", "edge", "dead"):
        if not np.array_equal(np.asarray(source[name])[keep], saved[name]):
            raise ValueError(f"Reference export changed {name}")


def normalization_diagnostics(raw, normalized, labels, metadata):
    if len(raw.points) != len(normalized.points):
        raise ValueError("Normalization changed row count")
    for name in ("X", "Y", "return_number", "number_of_returns", "source_row"):
        if not np.array_equal(raw[name], normalized[name]):
            raise ValueError(f"Normalization changed {name}")
    for name in ("scales", "offsets"):
        if not np.array_equal(getattr(raw.header, name), getattr(normalized.header, name)):
            raise ValueError(f"Normalization changed coordinate {name}")
    if "tree_index" in normalized.point_format.dimension_names or normalized.header.parse_crs() is not None:
        raise ValueError("Unexpected annotations or CRS in normalized geometry")
    z = np.asarray(normalized.z)
    if not np.isfinite(z).all() or not np.isin(normalized.classification, [1, 2]).all():
        raise ValueError("Invalid normalized heights or geometric classes")
    ground = np.asarray(normalized.classification) == 2
    xy = np.column_stack((raw.x, raw.y))
    ground_xy = xy[ground]
    hull = ConvexHull(ground_xy)
    inside = Delaunay(ground_xy[hull.vertices]).find_simplex(xy, tol=1e-10) >= 0
    heights = []
    # Sorting once keeps instance diagnostics linear after the sort.
    order = np.argsort(labels, kind="stable")
    ids, starts = np.unique(labels[order], return_index=True)
    maxima = np.maximum.reduceat(z[order], starts)
    for label, maximum in zip(ids, maxima):
        if label == 0:
            continue
        tree = metadata["trees"][int(label)]
        heights.append(dict(tree=int(label), category=tree["c"],
                            published_height=tree["h"], max_point_AGL=float(maximum),
                            difference_m=float(maximum - tree["h"])))
    differences = np.array([h["difference_m"] for h in heights])
    stats = dict(ground_points=int(ground.sum()), negative_AGL_fraction=float(np.mean(z < 0)),
                 below_minus_05_fraction=float(np.mean(z < -0.5)),
                 outside_ground_hull_fraction=float(np.mean(~inside)),
                 ground_abs_AGL_max=float(np.abs(z[ground]).max()),
                 AGL_min=float(z.min()), AGL_max=float(z.max()),
                 height_difference_median=float(np.median(differences)),
                 height_difference_abs_max=float(np.abs(differences).max()))
    return stats, heights


def write_csv(path, rows):
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def output_hashes(out):
    return {str(p.relative_to(out)): audit.file_hash(p) for p in sorted(out.rglob("*"))
            if p.is_file() and p != out / "manifest.json"}


def run(root, declaration_dir, out, plots, rscript="Rscript"):
    plots = select_plots(plots)
    if out.parent != root or out.exists() or out.name in ("source", "model"):
        raise ValueError("Use a new immediate output directory; preserve prior attempts")
    check_declaration(root, declaration_dir)
    _, protected = audit.workspace_inventory(root, out)
    metadata = yaml.safe_load((root / "source/plot_data.yaml").read_text())
    code = {p: audit.file_hash(REPO / p) for p in CODE_FILES}
    parent_hash = audit.file_hash(declaration_dir / "declaration.json")
    out.mkdir()
    results = []
    for plot in plots:
        directory = out / plot
        directory.mkdir()
        started = time.monotonic()
        result = dict(plot=plot, status="failed", error="")
        try:
            source = laspy.read(root / f"source/training/plot_{plot}.las")
            keep, rows, inventory = validate_points(source, metadata[int(plot)])
            inventory["coordinate_frame"] = f"FGI-EMIT/19351234/plot_{plot}"
            export_inputs(source, keep, rows, directory)
            (directory / "support.json").write_text(json.dumps(inventory, indent=2) + "\n")
            labels = np.asarray(source.tree_index)[keep].copy()
            del source, keep, rows
            with (directory / "normalization.log").open("w") as log:
                subprocess.run([rscript, str(REPO / CODE_FILES[1]), str(directory / "geometry.las"),
                                str(directory / "normalized.laz"), str(directory / "normalization.json")],
                               stdout=log, stderr=subprocess.STDOUT, check=True, timeout=600)
            stats, heights = normalization_diagnostics(laspy.read(directory / "geometry.las"),
                laspy.read(directory / "normalized.laz"), labels, metadata[int(plot)])
            write_csv(directory / "height_diagnostics.csv", heights)
            result.update({k: v for k, v in inventory.items() if not isinstance(v, (dict, list))})
            result.update(stats)
            result["status"] = "validated_structure"
        except Exception as error:
            result["error"] = f"{type(error).__name__}: {error}"
        result["elapsed_seconds"] = time.monotonic() - started
        (directory / "receipt.json").write_text(json.dumps(result, indent=2) + "\n")
        results.append(result)
        print(f"{plot}: {result['status']} {result['error']}", flush=True)
    check_declaration(root, declaration_dir)
    for relative, sha in protected.items():
        if audit.file_hash(root / relative) != sha:
            raise ValueError(f"Prior artifact changed: {relative}")
    if code != {p: audit.file_hash(REPO / p) for p in CODE_FILES}:
        raise ValueError("Preparation code/protocol changed during execution")
    fields = list(dict.fromkeys(k for row in results for k in row))
    write_csv(out / "summary.csv", [{k: r.get(k, "") for k in fields} for r in results])
    manifest = dict(schema_version=1, protocol="fgiemit-development-inputs-v1",
        declaration_directory=declaration_dir.name, declaration_sha256=parent_hash,
        plots=plots, complete_population=set(plots) == DEVELOPMENT,
        code_sha256=code, protected_sha256=protected, output_sha256=output_hashes(out),
        inference_run=False, calibration_fitted=False, evaluation_admitted=False,
        independent_AGL_validated=False, checkpoint_overlap="see separate provenance audit",
        numpy=np.__version__, scipy=scipy.__version__, laspy=laspy.__version__, python=sys.version,
        results=results)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return all(r["status"] == "validated_structure" for r in results)


def verify(root, out):
    manifest = json.loads((out / "manifest.json").read_text())
    declaration_dir = root / manifest["declaration_directory"]
    check_declaration(root, declaration_dir)
    if audit.file_hash(declaration_dir / "declaration.json") != manifest["declaration_sha256"]:
        raise ValueError("Original declaration changed")
    for relative, sha in manifest["protected_sha256"].items():
        path = (root / relative).resolve()
        if not path.is_relative_to(root) or audit.file_hash(path) != sha:
            raise ValueError(f"Prior artifact changed: {relative}")
    if manifest["code_sha256"] != {p: audit.file_hash(REPO / p) for p in CODE_FILES}:
        raise ValueError("Preparation code/protocol changed")
    if output_hashes(out) != manifest["output_sha256"]:
        raise ValueError("Prepared output changed")
    print("Original declaration, prior artifacts and all prepared outputs verified")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--declaration", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--plots", help="Declared development IDs only; default all ten")
    parser.add_argument("--rscript", default="Rscript")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    root, out = args.root.resolve(strict=True), args.out.resolve()
    if args.verify:
        verify(root, out)
    else:
        declaration = args.declaration or root / "development_declaration"
        if not run(root, declaration.resolve(strict=True), out, args.plots, args.rscript):
            raise SystemExit("Some declared development inputs failed; inspect preserved receipts")


if __name__ == "__main__":
    main()
