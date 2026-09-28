"""Fixed development matrix and symmetric, source-row height reductions."""
import math

import numpy as np

from prepare_fgiemit_development import DEVELOPMENT

ARMS = ("chm_vwf", "segmentanytree", "forestformer3d")
POLICIES = ("max_agl", "isolated_top_agl", "historical_raw")
PILOT = ("1001", "1019", "1027")


def apex_profiles(raw_xyz, agl_xyz, labels, source_rows):
    """Same reducer for references/predictions; no metadata heights or matching."""
    raw, agl = np.asarray(raw_xyz), np.asarray(agl_xyz)
    labels, rows = np.asarray(labels), np.asarray(source_rows)
    if (raw.ndim != 2 or raw.shape[1] != 3 or raw.shape != agl.shape or
            labels.shape != (len(raw),) or rows.shape != labels.shape or
            not np.isfinite(raw).all() or not np.isfinite(agl).all() or
            not np.array_equal(raw[:, :2], agl[:, :2])):
        raise ValueError("Height profiles require aligned finite raw/AGL rows")
    if any(not np.all(np.isfinite(v) & (v >= 0) & (v == np.floor(v))) for v in (labels, rows)):
        raise ValueError("Invalid instance or source row identity")
    if len(np.unique(rows)) != len(rows):
        raise ValueError("Source row identities must be unique, even at coincident XYZ")
    positive = np.flatnonzero(labels > 0)
    order = positive[np.argsort(labels[positive], kind="stable")]
    ids, starts, counts = np.unique(labels[order], return_index=True, return_counts=True)
    output = []
    for label, start, count in zip(ids, starts, counts):
        members = order[start:start + count]
        agl_order = members[np.lexsort((rows[members], -agl[members, 2]))]
        raw_order = members[np.lexsort((rows[members], -raw[members, 2]))]
        top = agl_order[0]
        gap = float(agl[top, 2] - agl[agl_order[1], 2]) if count > 1 else None
        trimmed = gap is not None and gap > 0.25
        alternate = agl_order[1] if trimmed else top
        for policy, selected, xyz in ((POLICIES[0], top, agl),
                                       (POLICIES[1], alternate, agl),
                                       (POLICIES[2], raw_order[0], raw)):
            output.append(dict(instance=int(label), policy=policy, points=int(count),
                source_row=int(rows[selected]), x=float(xyz[selected, 0]),
                y=float(xyz[selected, 1]), z=float(xyz[selected, 2]),
                top_AGL_gap=gap, trimmed=bool(trimmed and policy == POLICIES[1])))
    return output


def chm_parameters(frdens, pdens):
    if not all(math.isfinite(v) for v in (frdens, pdens)) or frdens < 1 or pdens < frdens:
        raise ValueError("Invalid measured density; no upsampling or low-density substitution")
    return dict(resolution_m=0.25 if frdens >= 8 else 0.5 if frdens >= 4 else 1.0,
                mean_smoothing_cells=0 if frdens >= 8 else 3,
                vwf_slope=0.10, vwf_min_m=3, vwf_max_m=5, min_height_m=2,
                first_returns_only=True, construction="lasR_TIN_then_pit_fill")


def build_matrix(prepared, provenance, folds):
    plots = prepared["plots"]
    if (set(plots) != DEVELOPMENT or len(plots) != 10 or not prepared["complete_population"] or
            prepared["inference_run"] or prepared["calibration_fitted"]):
        raise ValueError("Require the complete declared development population")
    results = {row["plot"]: row for row in prepared["results"]}
    if (set(results) != DEVELOPMENT or len(prepared["results"]) != 10 or
            any(r["status"] != "validated_structure" for r in results.values())):
        raise ValueError("Every declared development input must pass validation")
    if len(folds) != 10 or {f["validation_plot"] for f in folds} != DEVELOPMENT:
        raise ValueError("Require all ten declared whole-plot folds")
    for fold in folds:
        if (len(fold["calibration_plots"]) != 9 or
                set(fold["calibration_plots"]) != DEVELOPMENT - {fold["validation_plot"]} or
                fold["fold"] != f"leave_{fold['validation_plot']}_out"):
            raise ValueError("Calibration must use exactly the other nine development plots")
    if not provenance["checkpoint_identity_verified"] or provenance["inference_run"]:
        raise ValueError("Require the verified candidate checkpoint receipt")
    cells, calibration = [], []
    for plot in sorted(DEVELOPMENT):
        r = results[plot]
        if r["coordinate_frame"] != f"FGI-EMIT/19351234/plot_{plot}":
            raise ValueError("Plot-local frames must not be mixed")
        config = chm_parameters(r["frdens"], r["pdens"])
        for arm in ARMS:
            file = f"{plot}/{'normalized.laz' if arm == 'chm_vwf' else 'geometry.las'}"
            cells.append(dict(plot=plot, arm=arm, rung="native", state="planned",
                coordinate_frame=r["coordinate_frame"], input=file,
                input_sha256=prepared["output_sha256"][file], reference_count=r["reference_trees"],
                retained_points=r["retained_points"], frdens=r["frdens"], pdens=r["pdens"],
                fold=f"leave_{plot}_out", pilot=plot in PILOT,
                config=config if arm == "chm_vwf" else dict(
                    layout="whole_scene" if arm == "forestformer3d" else "existing_upstream_pipeline",
                    passes=1, additional_score_cutoff=None,
                    checkpoint_sha256=provenance[arm]["sha256"], image=provenance["images"][arm]),
                mask_track=arm != "chm_vwf", detection_track=True))
    scores = dict(chm_vwf="AGL_height_proxy", segmentanytree="retained_instance_point_count",
                  forestformer3d="mean_native_ff3d_score")
    for fold in sorted(folds, key=lambda f: f["validation_plot"]):
        for arm in ARMS:
            for target in (("apex_max_agl",) if arm == "chm_vwf" else ("apex_max_agl", "mask_iou_0.5")):
                calibration.append(dict(fold=fold["fold"], validation_plot=fold["validation_plot"],
                    calibration_plots=fold["calibration_plots"], arm=arm, target=target,
                    confidence_feature=scores[arm], state="planned"))
    return dict(cells=cells, calibration_cells=calibration,
        pilot_plots=list(PILOT), arm_order=list(ARMS), timeout_seconds=3600, concurrency=1,
        primary_mask=dict(iou=0.5, min_points=40, min_raw_Z_extent_m=1.5,
                          matcher="score_instance_cell", preserve_background=True),
        detection=dict(matcher="audit_apex_match", xy_m=4, absolute_z_m=5,
                       default_policy="max_agl", paired_instance_diagnostics=list(POLICIES[1:]),
                       isolated_top_gap_m=0.25, tie_break="lowest_source_row"),
        calibration=dict(method="weighted_tie_aggregated_PAVA_linear_interpolation",
            min_distinct_scores=2, require_both_labels=True, out_of_range="unavailable",
            bins=10, metrics=["Brier", "ECE", "coverage"], threshold_search=False),
        pooling=dict(primary_requires_complete_population=True, sum_counts_before_rates=True,
                     bootstrap_resamples=1000, bootstrap_seed=20260923),
        overlap_policy="conditional_development_only_unknown_upstream_overlap",
        runner_validated=False, execution_enabled=False, reserve_evaluation_enabled=False,
        inference_run=False, calibration_fitted=False)
