#!/usr/bin/env python3
"""Export the declared same-forward-pass TreeisoNet counterfactual labels."""
import argparse
import json
import laspy
import numpy as np


def export(input_path, archive, output):
    cloud = laspy.read(input_path)
    data = np.load(archive)
    xyz = np.column_stack([cloud.x, cloud.y, cloud.z])
    if xyz.shape != data["xyz"].shape or not np.allclose(xyz, data["xyz"], atol=1e-8, rtol=0):
        raise ValueError("Diagnostic labels lost their input point correspondence")
    ids = data["raw_ids"].astype(np.int32)
    shifted = np.where(data["shifted_z"] >= data["hmin"], ids, 0)
    physical = np.where(xyz[:, 2] >= data["hmin"], ids, 0)
    supported = np.where(data["support"], physical, 0)
    np.testing.assert_array_equal(supported, data["labels"])
    for name, labels in (("shifted", shifted), ("physical", physical), ("supported", supported)):
        cloud.add_extra_dim(laspy.ExtraBytesParams(name=name, type=np.int32))
        cloud[name] = labels
    cloud.write(output)
    stats = dict(points=len(ids), seeds=len(data["seeds"]),
                 min_height=float(xyz[:, 2].min()) if len(xyz) else None,
                 unsupported_points=int((~data["support"]).sum()),
                 unsupported_assigned=int(((~data["support"]) & (ids > 0)).sum()),
                 height_changed_points=int((shifted != physical).sum()),
                 support_changed_points=int((physical != supported).sum()))
    with open(str(output) + ".json", "w") as stream:
        json.dump(stats, stream, indent=2)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input")
    parser.add_argument("archive")
    parser.add_argument("output")
    args = parser.parse_args()
    export(args.input, args.archive, args.output)
