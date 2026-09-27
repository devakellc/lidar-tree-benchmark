#!/usr/bin/env python3
"""Assemble verified native FGI detectors, compare development fusion, export products."""
import argparse
import csv
from pathlib import Path
import subprocess

import laspy
import numpy as np

import prepare_fgiemit_reserve as prepared_inputs
import run_fgiemit_reserve as reserve
import summarize_fgiemit_development as summary

REPO = Path(__file__).resolve().parents[1]
FILES = ("scripts/run_ensemble_pipeline.py", "scripts/fgiemit_pipeline_lib.R",
         "scripts/analyze_fgiemit_pipeline.R", "scripts/assemble_metapipeline.R",
         "docs/final-ensemble-pipeline.md")
read_json, write_json = reserve.read_json, reserve.write_json
read_csv = prepared_inputs.policy.calibration.read_csv
write_csv = summary.write_csv
ARMS = prepared_inputs.policy.ARMS


def get_inputs(root, stage, prepared, run):
    if stage == "reserve":
        receipt = reserve.verify(root, prepared, run)
        matrix = read_json(prepared / "contract/matrix.json")
        references = prepared / "contract/reference_apexes.csv"
        geometries = prepared / "inputs"
        parents = {str(run / "run.json"): prepared_inputs.file_hash(run / "run.json"),
                   str(prepared / "manifest.json"): prepared_inputs.file_hash(prepared / "manifest.json")}
        calibration = None
    else:
        context = prepared_inputs.preflight(root)
        freeze = read_json(root / "development_policy/freeze.json")
        calibration = Path(freeze["calibration_directory"])
        parent = read_json(calibration / "calibration.json")
        run = Path(parent["run_directory"])
        receipt = read_json(run / "run.json")
        matrix = read_json(root / "development_comparison/matrix.json")
        references = root / "development_comparison/reference_apexes.csv"
        geometries = root / "development_inputs"
        parents = {str(root / "development_policy/freeze.json"):
            context["parent_sha256"]["freeze.json"],
            str(run / "run.json"): prepared_inputs.file_hash(run / "run.json"),
            str(calibration / "calibration.json"): prepared_inputs.file_hash(calibration / "calibration.json")}
    return receipt, matrix, references, geometries, parents, calibration


def input_tables(root, receipt, matrix, references):
    declarations = {reserve.development.key(c): c for c in matrix["cells"]}
    cells, predictions = [], []
    for record in receipt["cells"]:
        cell = declarations[reserve.development.key(record)]
        accepted = record["state"] in reserve.SUCCESS
        source = (root / record["source_directory"]).resolve()
        cells.append(dict(plot=record["plot"], arm=record["arm"], state=record["state"],
            error=record.get("error", ""), predictions=record.get("predictions") if accepted else None,
            reference_count=cell["reference_count"], retained_points=cell["retained_points"],
            frdens=cell["frdens"], pdens=cell["pdens"], coordinate_frame=cell["coordinate_frame"],
            source_directory=str(source), input_sha256=cell["input_sha256"]))
        if accepted:
            rows = [r for r in read_csv(source / "prediction_apexes.csv") if r["policy"] == "max_agl"]
            if len(rows) != record["predictions"]:
                raise ValueError("Accepted apex population differs from receipt")
            predictions.extend(dict(plot=record["plot"], arm=record["arm"],
                **{k: r[k] for k in ("instance", "x", "y", "z", "confidence")}) for r in rows)
    refs = [r for r in read_csv(references) if r["policy"] == "max_agl"]
    return cells, predictions, refs


def pooled_metrics(receipt):
    if not receipt["complete_detector_matrix"]:
        return []
    rows = summary.metric_rows(receipt)
    groups = sorted({(r["arm"], r["target"]) for r in rows})
    pooled = []
    for arm, target in groups:
        group = [r for r in rows if (r["arm"], r["target"]) == (arm, target)]
        counts = {k: sum(r[k] for r in group) for k in summary.COUNTS}
        tp, npred, nref = counts["TP"], counts["n_pred"], counts["n_ref"]
        row = dict(arm=arm, target=target, n_cells=len(group), **counts,
            precision=tp/npred if npred else None, recall=tp/nref,
            F1=2*tp/(npred+nref), sum_iou=None, sum_maxiou=None, coverage=None, SQ=None, PQ=None)
        for c in "ABCD":
            row.update({k+c: None for k in ("n_", "tp_", "rec_")})
        if target == "mask_iou_0.5":
            si, sm = (sum(r[k] for r in group) for k in ("sum_iou", "sum_maxiou"))
            row.update(sum_iou=si, sum_maxiou=sm, coverage=sm/nref, SQ=si/tp if tp else None,
                       PQ=si/(tp+.5*(counts["FP"]+counts["FN"])))
            for c in "ABCD":
                n, t = (sum(r[k+c] for r in group) for k in ("n_", "tp_"))
                row.update({"n_"+c: n, "tp_"+c: t, "rec_"+c: t/n if n else None})
        pooled.append(row)
    return pooled


def export_instances(geometry_dir, source, directory):
    """Export separate full-row predicted masks in the declared local AGL frame."""
    raw = laspy.read(geometry_dir / "geometry.las")
    native = laspy.read(source / "model_io/predictions.laz")
    labels, scores = reserve.engine.aligned_labels(raw, native, "forestformer3d")
    labels, _ = reserve.engine.fixed_filter(labels, np.asarray(raw.z), scores)
    accepted = np.loadtxt(source / "prediction_labels.csv", dtype=np.int64, skiprows=1, ndmin=1)
    if not np.array_equal(labels, accepted):
        raise ValueError("Exported masks differ from the admitted fixed filter")
    cloud = laspy.read(geometry_dir / "normalized.laz")
    if not np.array_equal(raw.source_row, cloud.source_row):
        raise ValueError("Mask geometry changed source identity")
    cloud.add_extra_dim(laspy.ExtraBytesParams(name="pred_instance", type="uint32"))
    cloud.pred_instance = labels
    cloud.write(directory / "instance_masks.laz")
    saved = laspy.read(directory / "instance_masks.laz")
    if not np.array_equal(saved.pred_instance, labels) or not np.array_equal(saved.source_row, raw.source_row):
        raise ValueError("Mask export changed labels or row identity")
    ids = np.unique(labels[labels > 0])
    return dict(mask_type="predicted_instances", arm="forestformer3d", background_label=0,
        points=len(labels), instances=len(ids), height_datum="geometric_AGL", epsg=None,
        annotation_fields_present=False, refinement_run=False, mensuration_validated=False)


def assemble(root, stage, prepared, run, out, method="selected_policy", execute=False):
    prepared_inputs.check_location(root, out, creating=True)
    if stage == "reserve":
        if method != "selected_policy":
            raise ValueError("Reserve policy is frozen; fusion is development-only")
        if prepared is None or run is None:
            raise ValueError("Reserve stage needs prepared inputs and a run directory")
        if execute and not run.exists():
            reserve.run(root, prepared, run)
        if out == prepared or out == run or out.is_relative_to(prepared) or out.is_relative_to(run):
            raise ValueError("Product output must not modify prepared inputs or the detector run")
    elif execute:
        raise ValueError("Development assembly reuses sealed outputs without inference")
    receipt, matrix, references, geometries, parents, calibration = get_inputs(root, stage, prepared, run)
    if method not in ("selected_policy", "union_all", "consensus_2of3", "union_point", "consensus_point", "weighted_all"):
        raise ValueError("Unknown explicit development fusion method")
    code = prepared_inputs.policy.hashes(REPO, FILES)
    out.mkdir()
    cells, predictions, refs = input_tables(root, receipt, matrix, references)
    write_csv(out / "input_cells.csv", cells)
    write_csv(out / "input_predictions.csv", predictions, ["plot", "arm", "instance", "x", "y", "z", "confidence"])
    write_csv(out / "input_references.csv", refs)
    if calibration:
        (out / "input_calibration.csv").write_bytes((calibration / "predictions.csv").read_bytes())
        (out / "input_calibration_status.csv").write_bytes((calibration / "status.csv").read_bytes())
    with (out / "analysis.log").open("w") as log:
        subprocess.run(["Rscript", str(REPO / "scripts/analyze_fgiemit_pipeline.R"), str(out), stage],
                       stdout=log, stderr=subprocess.STDOUT, timeout=600, check=True, cwd=REPO)
    complete = receipt["complete_detector_matrix"]
    metrics = pooled_metrics(receipt)
    if complete:
        write_csv(out / "baseline_metrics.csv", metrics)
        write_csv(out / "baseline_cells.csv", summary.metric_rows(receipt))
        # An independent score replay through the assembly must reproduce controls.
        controls = {r["product"]: r for r in read_csv(out / "pooled.csv") if r["product"] in ARMS}
        for row in metrics:
            if row["target"] == "apex_max_agl" and any(
                    int(float(controls[row["arm"]][k])) != row[k] for k in summary.COUNTS):
                raise ValueError("Assembly changed baseline matching or prediction support")
    selected = "forestformer3d" if method == "selected_policy" else method
    products = read_csv(out / "products.csv") if complete else []
    detections = read_csv(out / "detections.csv") if complete else []
    deliverables = []
    for cell in cells:
        if cell["arm"] != "forestformer3d":
            continue
        plot = cell["plot"]
        state = next((r["state"] for r in products if r["plot"] == plot and r["product"] == selected), "blocked")
        record = dict(plot=plot, detection_product=selected, state=state,
            coordinate_frame=cell["coordinate_frame"], frdens=cell["frdens"], pdens=cell["pdens"],
            detection_count=None, instance_product="forestformer3d", instance_count=None)
        if complete and state in ("completed", "completed_empty"):
            directory = out / "products" / plot
            directory.mkdir(parents=True)
            trees = [r for r in detections if r["plot"] == plot and r["product"] == selected]
            write_csv(directory / "treetops.csv", trees, ["plot", "product", "instance", "x", "y", "z"])
            masks = export_instances(geometries / plot, Path(cell["source_directory"]), directory)
            record.update(detection_count=len(trees), instance_count=masks["instances"])
            write_json(directory / "product.json", dict(record, mask=masks,
                detection_and_mask_ids_shared=selected == "forestformer3d",
                detection_height_datum="geometric_AGL", crown_width_or_DBH_claim=False,
                raw_score_not_probability=True, reference_support="all_original_AD_references"))
        deliverables.append(record)
    write_csv(out / "deliverables.csv", deliverables)
    if any(prepared_inputs.file_hash(Path(p)) != h for p,h in parents.items()) or code != prepared_inputs.policy.hashes(REPO, FILES):
        raise ValueError("Pipeline parents or code changed during assembly")
    manifest = dict(schema_version=1, stage=stage, method=method, selected_product=selected,
        development_root=str(root), prepared_directory=str(prepared) if prepared else None,
        run_directory=str(run) if run else None, parent_sha256=parents, code_sha256=code,
        output_sha256=prepared_inputs.output_hashes(out), complete_detector_matrix=complete,
        product_ready=complete and all(r["state"] in ("completed", "completed_empty") for r in deliverables),
        fusion_promoted=False, primary_policy="forestformer3d", calibration_fitted=False,
        reserve_fusion_enabled=False, upstream_training_overlap="unknown",
        independent_AGL_validated=False, sparse_density_routing_enabled=False)
    write_json(out / "manifest.json", manifest)
    print(f"Pipeline {stage}: complete={complete}, product={selected}, ready={manifest['product_ready']}", flush=True)
    return manifest


def verify(root, out):
    prepared_inputs.check_location(root, out)
    manifest = read_json(out / "manifest.json")
    stage, method = manifest["stage"], manifest["method"]
    if (manifest["schema_version"] != 1 or stage not in ("development", "reserve") or
            method not in ("selected_policy", "union_all", "consensus_2of3", "union_point", "consensus_point", "weighted_all") or
            (stage == "reserve" and method != "selected_policy") or
            manifest["selected_product"] != ("forestformer3d" if method == "selected_policy" else method) or
            manifest["primary_policy"] != "forestformer3d" or manifest["upstream_training_overlap"] != "unknown"):
        raise ValueError("Pipeline policy or stage changed")
    prepared = Path(manifest["prepared_directory"]) if manifest["prepared_directory"] else None
    run = Path(manifest["run_directory"]) if manifest["run_directory"] else None
    receipt, _, _, _, parents, _ = get_inputs(root, manifest["stage"], prepared, run)
    products = read_csv(out / "deliverables.csv")
    plots = list(prepared_inputs.policy.RESERVE) if stage == "reserve" else sorted(reserve.development.DEVELOPMENT)
    ready = receipt["complete_detector_matrix"] and all(r["state"] in ("completed", "completed_empty") for r in products)
    if (sorted(r["plot"] for r in products) != sorted(plots) or
            any(r["detection_product"] != manifest["selected_product"] or r["instance_product"] != "forestformer3d" for r in products) or
            manifest["product_ready"] != ready):
        raise ValueError("Pipeline readiness or deliverable population changed")
    if (manifest["development_root"] != str(root) or manifest["parent_sha256"] != parents or
            manifest["code_sha256"] != prepared_inputs.policy.hashes(REPO, FILES) or
            manifest["output_sha256"] != prepared_inputs.output_hashes(out) or
            manifest["complete_detector_matrix"] != receipt["complete_detector_matrix"] or
            any(manifest[k] for k in ("fusion_promoted", "calibration_fitted", "reserve_fusion_enabled",
                                      "independent_AGL_validated", "sparse_density_routing_enabled"))):
        raise ValueError("Pipeline scope, parents, code or product files changed")
    print("Pipeline parent chain and all exported product hashes verified", flush=True)
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--stage", choices=("development", "reserve"), default="reserve")
    parser.add_argument("--prepared", type=Path)
    parser.add_argument("--run", type=Path)
    parser.add_argument("--method", default="selected_policy")
    parser.add_argument("--execute", action="store_true", help="Execute a missing frozen reserve run once")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    root, out = args.root.resolve(strict=True), args.out.resolve()
    if args.verify:
        result = verify(root, out)
    else:
        result = assemble(root, args.stage, args.prepared.resolve() if args.prepared else None,
            args.run.resolve() if args.run else None, out, args.method, args.execute)
    if not result["product_ready"]:
        raise SystemExit(1)
