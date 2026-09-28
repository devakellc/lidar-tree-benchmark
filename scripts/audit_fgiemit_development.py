#!/usr/bin/env python3
"""Audit pinned training metadata/headers and reserve plots without scoring."""
import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys
import zipfile

import laspy
import yaml


TEST_PLOTS = {"1002", "1004", "1008", "1012", "1018", "1028"}
AUDITED_PLOTS = {"1001", "1019"}
RESERVED_PLOTS = {"1003", "1010", "1023"}
RELEASE_MD5 = {"plot_data.yaml": "0e5f69c28be31374bb3cf8faa03bded0",
               "training.zip": "b1c5ee7e9c166dd7ff377539944e5002"}


def stream_hash(stream, algorithm="sha256"):
    digest = hashlib.new(algorithm)
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(chunk)
    return digest.hexdigest()


def file_hash(path, algorithm="sha256"):
    with Path(path).open("rb") as stream:
        return stream_hash(stream, algorithm)


def metadata_rows(metadata):
    rows = []
    for key, item in metadata.items():
        plot = str(key)
        if not re.fullmatch(r"\d{4}", plot) or type(item["test"]) is not bool:
            raise ValueError("Invalid plot identity or split flag")
        area, density = float(item["area"]), float(item["density"])
        if not all(math.isfinite(x) and x > 0 for x in (area, density)):
            raise ValueError("Invalid published area or stand density")
        counts = {c: item["n_trees"][c] for c in ("A", "B", "C", "D", "all")}
        if any(type(v) is not int or v < 0 for v in counts.values()):
            raise ValueError("Invalid published tree count")
        if sum(counts[c] for c in "ABCD") != counts["all"]:
            raise ValueError("Published crown-category counts disagree")
        rows.append(dict(plot=plot, publisher_split="test" if item["test"] else "training",
                         published_area_ha=area, published_trees_per_ha=density,
                         **{f"n_{c}": value for c, value in counts.items()}))
    if len({r["plot"] for r in rows}) != len(rows):
        raise ValueError("Duplicate plot identity")
    return sorted(rows, key=lambda r: r["plot"])


def declare_split(rows, previously_processed):
    training = {r["plot"] for r in rows if r["publisher_split"] == "training"}
    test = {r["plot"] for r in rows if r["publisher_split"] == "test"}
    if test != TEST_PLOTS or len(training) != 13 or not AUDITED_PLOTS <= training:
        raise ValueError("Metadata does not match the pinned published split")
    unexpected = (set(previously_processed) & training) - AUDITED_PLOTS
    if unexpected:
        raise ValueError(f"Unexpected prior processing; do not replace reserve: {sorted(unexpected)}")
    candidates = sorted((r for r in rows if r["plot"] in training - AUDITED_PLOTS),
                        key=lambda r: (r["published_trees_per_ha"], r["plot"]))
    quotient, remainder = divmod(len(candidates), 3)
    strata, reserve = {}, set()
    start = 0
    for index in range(3):
        size = quotient + (index < remainder)
        group = candidates[start:start + size]
        reserve.add(group[(size - 1) // 2]["plot"])
        strata.update({r["plot"]: index + 1 for r in group})
        start += size
    if reserve != RESERVED_PLOTS:
        raise ValueError("Metadata selection differs from the declared reserve")
    out = []
    for row in rows:
        plot = row["plot"]
        role = "historical_test" if plot in test else (
            "evaluation_reserve" if plot in reserve else "development")
        out.append(dict(row, role=role, selection_stratum=strata.get(plot, ""),
                        development_fold=f"leave_{plot}_out" if role == "development" else "",
                        prior_audit=plot in AUDITED_PLOTS,
                        workspace_evidence_files=len(previously_processed.get(plot, [])),
                        evaluation_admitted=False))
    return out


def workspace_inventory(root, excluded):
    """Inventory artifact names, not metric values, outside the source release."""
    evidence, protected = {}, {}
    for directory, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in ("source", "model", "__pycache__")
                         and (Path(directory) / d).resolve() != excluded)
        for name in sorted(files):
            path = Path(directory) / name
            relative = path.relative_to(root)
            ids = {part for part in relative.parts[:-1] if re.fullmatch(r"\d{4}", part)}
            match = re.match(r"(?:plot_)?(\d{4})(?:[_.]|$)", name)
            if match:
                ids.add(match[1])
            for plot in ids:
                evidence.setdefault(plot, []).append(str(relative))
            if path.suffix.lower() in (".json", ".csv", ".rds", ".yaml"):
                protected[str(relative)] = file_hash(path)
    return evidence, protected


def audit_header(path, area_ha):
    with laspy.open(path) as reader:
        h = reader.header
        returns = [int(n) for n in h.number_of_points_by_return]
        count = int(h.point_count)
        if count <= 0 or sum(returns) != count or returns[0] <= 0:
            raise ValueError(f"Incomplete header return counts: {path.name}")
        if h.offset_to_point_data + count * h.point_format.size > path.stat().st_size:
            raise ValueError(f"Truncated source file: {path.name}")
        if "tree_index" not in h.point_format.extra_dimension_names:
            raise ValueError(f"Missing annotation field: {path.name}")
        bounds = [float(x) for x in (*h.mins, *h.maxs)]
        if not all(math.isfinite(x) for x in bounds):
            raise ValueError(f"Nonfinite header bounds: {path.name}")
        crs = h.parse_crs()
        # Current release is plot-local. A later CRS-bearing file is not this declaration.
        if crs is not None:
            raise ValueError(f"Unexpected source CRS: {path.name}")
        area = area_ha * 10000
        return dict(header_points=count, header_first_returns=returns[0],
                    header_return_counts=returns, point_format=int(h.point_format.id),
                    declared_crs=None, coordinate_frame="plot_local_metric",
                    height_datum="local_z_not_verified_AGL", bounds=bounds,
                    estimated_pdens=count / area, estimated_frdens=returns[0] / area,
                    density_basis="header_counts_over_rounded_published_area",
                    density_admitted=False)


def verify(declaration, root):
    if declaration["schema_version"] != 1:
        raise ValueError("Unsupported declaration schema")
    for group in ("source_sha256", "protected_sha256"):
        for relative, expected in declaration[group].items():
            path = (root / relative).resolve()
            if not path.is_relative_to(root) or file_hash(path) != expected:
                raise ValueError(f"Protected input/artifact changed: {relative}")
    evidence, _ = workspace_inventory(root, root / declaration["output_directory"])
    for plot in declaration["evaluation_reserve"]:
        if evidence.get(plot):
            raise ValueError(f"Evaluation reserve has processing evidence: {plot}")
    repo = Path(__file__).resolve().parents[1]
    if (file_hash(__file__) != declaration["code_sha256"] or
            file_hash(repo / "docs/fgiemit-development-protocol.md") != declaration["protocol_sha256"]):
        raise ValueError("Audit code or protocol changed; preserve the old declaration")


def run_audit(root, out):
    root, out = root.resolve(strict=True), out.resolve()
    if out.parent != root or out.exists():
        raise ValueError("OUT must be a new immediate child of ROOT; preserve previous runs")
    source = root / "source"
    for name, expected in RELEASE_MD5.items():
        if file_hash(source / name, "md5") != expected:
            raise ValueError(f"Pinned release checksum mismatch: {name}")
    metadata = yaml.safe_load((source / "plot_data.yaml").read_text())
    rows = metadata_rows(metadata)
    evidence, protected = workspace_inventory(root, out)
    split = declare_split(rows, evidence)
    source_hashes = {f"source/{name}": file_hash(source / name) for name in RELEASE_MD5}
    headers = {}
    training = [r for r in split if r["publisher_split"] == "training"]
    with zipfile.ZipFile(source / "training.zip") as archive:
        members = [i.filename for i in archive.infolist() if i.filename.endswith(".las")]
        expected = {f"training/plot_{r['plot']}.las" for r in training}
        if len(members) != len(expected) or set(members) != expected:
            raise ValueError("Archive training membership differs from metadata")
        for row in training:
            member = f"training/plot_{row['plot']}.las"
            path = source / member
            sha = file_hash(path)
            with archive.open(member) as stream:
                if stream_hash(stream) != sha:
                    raise ValueError(f"Extracted source differs from pinned archive: {member}")
            source_hashes[f"source/{member}"] = sha
            headers[row["plot"]] = audit_header(path, row["published_area_ha"])
            print(f"Verified source and header: {row['plot']}", flush=True)
    repo = Path(__file__).resolve().parents[1]
    protocol = repo / "docs/fgiemit-development-protocol.md"
    declaration = dict(schema_version=1, protocol="fgiemit-metadata-development-v1",
        output_directory=out.name,
        release="https://doi.org/10.5281/zenodo.19351234", source_md5=RELEASE_MD5,
        selection="stand-density ranks; groups 4/4/3; lower median reserved",
        development=[r["plot"] for r in split if r["role"] == "development"],
        evaluation_reserve=sorted(RESERVED_PLOTS), historical_test=sorted(TEST_PLOTS),
        rungs=["native"], inference_run=False, scores_read=False,
        point_records_parsed=False, calibration_fitted=False, evaluation_admitted=False,
        checkpoint_training_overlap="unknown", headers=headers, artifact_evidence=evidence,
        source_sha256=source_hashes, protected_sha256=protected,
        code_sha256=file_hash(__file__), protocol_sha256=file_hash(protocol),
        python=sys.version, laspy=laspy.__version__, pyyaml=yaml.__version__)
    # Check that all inventoried inputs/receipts stayed unchanged during the audit.
    verify(declaration, root)
    out.mkdir()
    with (out / "plot_inventory.csv").open("w", newline="") as stream:
        fields = list(split[0]) + ["header_points", "header_first_returns",
                                  "estimated_pdens", "estimated_frdens"]
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for row in split:
            writer.writerow(dict(row, **{k: headers.get(row["plot"], {}).get(k, "")
                                         for k in fields if k not in row}))
    folds = []
    for plot in declaration["development"]:
        folds.append(dict(fold=f"leave_{plot}_out", validation_plot=plot,
                          calibration_plots=[p for p in declaration["development"] if p != plot]))
    (out / "folds.json").write_text(json.dumps(folds, indent=2) + "\n")
    declaration["output_sha256"] = {name: file_hash(out / name)
                                      for name in ("plot_inventory.csv", "folds.json")}
    (out / "declaration.json").write_text(json.dumps(declaration, indent=2) + "\n")
    print(f"Declared 10 development plots and 3 reserved plots in {out}")
    return declaration


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if args.verify:
        declaration = json.loads((args.out / "declaration.json").read_text())
        verify(declaration, args.root.resolve(strict=True))
        for name, expected in declaration["output_sha256"].items():
            if file_hash(args.out / name) != expected:
                raise ValueError(f"Declaration output changed: {name}")
        print("Source, protected receipts and declaration outputs verified")
    else:
        run_audit(args.root, args.out)


if __name__ == "__main__":
    main()
