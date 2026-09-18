#!/usr/bin/env python3
"""Protect the earlier transfer experiments before whole-scene inference."""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from declare_transfer_audit import sha256


def verify(data):
    for path, expected in data["sha256"].items():
        if sha256(path) != expected:
            raise ValueError(f"Protected artifact changed: {path}")
    return len(data["sha256"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    path = args.root / "scene_assembly/declaration.json"
    if args.verify:
        count = verify(json.loads(path.read_text()))
        print(f"Verified {count} protected files")
        return
    old_path = args.root / "audit/declaration.json"
    old = json.loads(old_path.read_text())
    verify(old)
    repo = Path(__file__).resolve().parents[1]
    paths = {Path(p) for p in old["sha256"]}
    paths.add(repo / "docs/forestformer-scene-assembly-protocol.md")
    paths.add(repo / "results/frozen-transfer-audit-results.md")
    # Protect complete prior experiment trees, including interrupted attempts.
    for name in ("audit", "training"):
        paths.update(p for p in (args.root / name).rglob("*") if p.is_file())
    data = dict(declared_at=datetime.now(timezone.utc).isoformat(),
                split="training", plots=[1001, 1019],
                comparison=["archived_outer_cylinders", "native_whole_scene"],
                sha256={str(p.resolve()): sha256(p) for p in sorted(paths)})
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x") as stream:
        json.dump(data, stream, indent=2)
        stream.write("\n")
    print(f"Declared scene assembly: {len(data['sha256'])} protected files")


if __name__ == "__main__":
    main()
