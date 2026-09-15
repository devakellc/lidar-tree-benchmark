#!/usr/bin/env python3
"""Run the archived official evaluator on already aligned instance predictions."""
import argparse
import json
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--accuracy-dir", type=Path, required=True)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--metadata-dir", type=Path, required=True)
    parser.add_argument("--split", choices=("training", "test"), required=True)
    parser.add_argument("--plots", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.accuracy_dir.resolve()))
    from omegaconf import OmegaConf
    from accuracy import compute_accuracy_metrics

    config = OmegaConf.load(args.accuracy_dir / "cfgs" / "accuracy.yaml")
    config.data_path = str(args.data_dir.resolve())
    config.plot_metadata_path = str(args.metadata_dir.resolve())
    config.id_list = [int(x) for x in args.plots.split(",")]
    config.file_type = "laz"
    config.tree_pred_field = "tree_pred"
    config.metrics = ["precision", "recall", "f1", "cov", "ctg"]
    metrics = compute_accuracy_metrics(
        config, test=args.split == "test", return_metrics=True
    )
    if metrics is None:
        raise RuntimeError("Official evaluator found no predictions")
    with args.out.open("w") as handle:
        json.dump(OmegaConf.to_container(metrics), handle, indent=2, allow_nan=False)


if __name__ == "__main__":
    main()
