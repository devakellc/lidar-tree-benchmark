"""Cut thinned FGI-EMIT development inputs from the seeded row selection.

For each plot and target written by fgiemit_thin_select.R (rows.csv), keeps
the same source rows of the model input (geometry.las), the labels
(reference.laz) and the above-ground cloud (normalized.laz), with their
headers unchanged, so the admitted cell runner reads them like the native
inputs (docs/fgiemit-thinning-protocol.md). Development plots only.

    python3 scripts/fgiemit_thin_write.py <fgiemit root> <selection dir>
"""
import csv
import hashlib
import json
import sys
from pathlib import Path

import laspy
import numpy as np

DEV = {"1001", "1005", "1009", "1013", "1019", "1020", "1022", "1024", "1027", "1031"}
FILES = ("geometry.las", "reference.laz", "normalized.laz")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main(root, selection):
    root, selection = Path(root).resolve(), Path(selection).resolve()
    if root in selection.parents:
        raise ValueError("The selection must be outside the FGI-EMIT root")
    for rows_file in sorted(selection.glob("*/*/rows.csv")):
        variant, plot = rows_file.parent, rows_file.parent.parent.name
        if plot not in DEV:
            raise ValueError(f"Not a development plot: {plot}")
        keep = np.array([int(r["source_row"]) for r in csv.DictReader(rows_file.open())])
        receipt = {"plot": plot, "variant": variant.name, "rows": int(len(keep)), "files": {}}
        for name in FILES:
            src = laspy.read(root / "development_inputs" / plot / name)
            mask = np.isin(np.asarray(src.source_row), keep)
            if int(mask.sum()) != len(keep):
                raise ValueError(f"{plot} {variant.name} {name}: rows missing from the source")
            out = laspy.LasData(src.header)
            out.points = src.points[mask].copy()
            target = variant / name
            out.write(target)
            receipt["files"][name] = {"source_sha256": sha256(root / "development_inputs" / plot / name),
                                      "sha256": sha256(target)}
        (variant / "receipt.json").write_text(json.dumps(receipt, indent=2))
        print(plot, variant.name, len(keep))


if __name__ == "__main__":
    main(*sys.argv[1:3])
