#!/usr/bin/env python3
"""Seal or verify the bounded audit declaration before detector inference."""
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    declaration = args.root / "audit/declaration.json"
    if args.verify:
        data = json.loads(declaration.read_text())
        for path, expected in data["sha256"].items():
            if sha256(path) != expected:
                raise SystemExit(f"Protected input/artifact changed: {path}")
        print(f"Verified {len(data['sha256'])} protected files")
        return
    paths = [repo / "docs/frozen-transfer-audit-protocol.md"]
    paths += [args.root / name for name in
              ("scores.csv", "summary.csv", "run_manifest.json")]
    paths += sorted((args.root / "instances").rglob("*.laz"))
    paths += sorted((args.root / "runs").rglob("score.rds"))
    paths += [args.root / "source/plot_data.yaml"]
    paths += [args.root / f"source/training/plot_{pid}.las"
              for pid in (1001, 1019)]
    paths += [repo / "gpu/store/forestformer3d/ForestFormer3D/work_dirs/"
              "clean_forestformer/epoch_3000_fix.pth"]
    paths += [repo / f"gpu/store/treeaibox/als_{arm}.pth"
              for arm in ("treeloc", "treeoff")]
    paths += sorted((repo / "gpu/store/treeaibox").glob("*reclamation*.json"))
    data = dict(declared_at=datetime.now(timezone.utc).isoformat(),
                split="training", plots=[1001, 1019],
                frozen_commit="79c683adbc968c8424208b5570d99b0230a6003c",
                images=dict(segmentanytree="sha256:27ce258d8a5ab70bdc457523d373848d5065e7b8044d3ef7891ff9e53dee2bd2",
                            forestformer3d="sha256:fd60f5cdc5ae880af13b339f4aa1f1e891a3809c7f39fb15d2b5ff04978799f3"),
                sha256={str(path.resolve()): sha256(path) for path in paths})
    declaration.parent.mkdir(parents=True, exist_ok=True)
    with declaration.open("x") as stream:
        json.dump(data, stream, indent=2)
        stream.write("\n")
    print(f"Declared audit: {declaration}")


if __name__ == "__main__":
    main()
