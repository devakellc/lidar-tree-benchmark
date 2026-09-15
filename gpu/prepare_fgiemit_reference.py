#!/usr/bin/env python3
"""Retain FGI-EMIT labels when R LAS readers limit the number of extra fields."""
import argparse

import laspy
import numpy as np


def prepare_reference(source, destination):
    cloud = laspy.read(source)
    names = list(cloud.point_format.extra_dimension_names)
    if "tree_index" not in names:
        raise ValueError("FGI-EMIT reference is missing tree_index")
    labels = np.asarray(cloud.tree_index)
    if not np.all(np.isfinite(labels) & (labels >= 0) & (labels == np.floor(labels))):
        raise ValueError("Invalid reference instance labels")
    if not np.isin(cloud.classification, np.arange(6)).all():
        raise ValueError("Unknown FGI-EMIT semantic class")
    # Keep integer XYZ, scales, offsets, standard fields and tree_index verbatim.
    cloud.remove_extra_dims([name for name in names if name != "tree_index"])
    cloud.write(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source")
    parser.add_argument("destination")
    args = parser.parse_args()
    prepare_reference(args.source, args.destination)


if __name__ == "__main__":
    main()
