#!/usr/bin/env python3
"""Trace installed candidate weights without loading a model or point cloud."""
import argparse
import hashlib
import inspect
import json
from pathlib import Path
import subprocess
import zipfile

SAT_COMMIT = "a3561ed8447bbb7938f059ba65a3e9c97d6e2ee9"
# Git LFS pointer at the pinned SegmentAnyTree commit, not an unpinned download.
SAT_SHA256 = "0b4d74b4644e37a16f59008ad0f5c62894fc4d2d906f3abd803bbfc5b5dd803a"
FF_ARCHIVE_MD5 = "553d67379331966509076f3fbb409e57"


def inspect_checkpoint(path):
    """Read pickle opcodes as data; never unpickle or import the model runtime."""
    import hashlib
    import pickletools
    import re
    import zipfile
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    with zipfile.ZipFile(path) as archive:
        members = [n for n in archive.namelist() if n.endswith("/data.pkl")]
        if len(members) != 1:
            raise ValueError("Expected one checkpoint metadata pickle")
        strings = [arg for op, arg, _ in pickletools.genops(archive.read(members[0]))
                   if op.name in ("BINUNICODE", "SHORT_BINUNICODE", "UNICODE")]
    pattern = r"train|data_root|dataset|ann_file|treeins|forainet|for.instance|nibio|fgi|emit"
    evidence = sorted({line.strip() for value in strings for line in value.splitlines()
                       if re.search(pattern, line, re.IGNORECASE)})
    return dict(sha256=digest.hexdigest(), serialized_text_evidence=evidence,
                pickle_executed=False, model_loaded=False)


def command(args):
    return subprocess.check_output(args, text=True, timeout=90).strip()


def docker_read(image, args):
    return command(["docker", "run", "--rm", "--network", "none", "--read-only",
                    "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
                    "--entrypoint", args[0], image, *args[1:]])


def collect(gpu_root):
    ff_repo = gpu_root / "store/forestformer3d/ForestFormer3D"
    ff_archive = gpu_root / "store/forestformer3d/clean_forestformer.zip"
    ff_path = ff_repo / "work_dirs/clean_forestformer/epoch_3000_fix.pth"
    with ff_archive.open("rb") as stream:
        archive_md5 = hashlib.file_digest(stream, "md5").hexdigest()
    if archive_md5 != FF_ARCHIVE_MD5:
        raise ValueError("ForestFormer3D archive differs from the official release pin")
    ff = inspect_checkpoint(ff_path)
    with zipfile.ZipFile(ff_archive) as archive:
        with archive.open("clean_forestformer/epoch_3000_fix.pth") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != ff["sha256"]:
                raise ValueError("Installed ForestFormer3D weights differ from the archive")
    ff.update(release="https://doi.org/10.5281/zenodo.16742708", archive_md5=archive_md5,
              checkpoint=str(ff_path),
              source_commit=command(["git", "-C", str(ff_repo), "rev-parse", "HEAD"]),
              source_status=command(["git", "-C", str(ff_repo), "status", "--short"]),
              documented_training_dataset="FOR-InstanceV2 (ForAINetV2 in checkpoint config)")
    tracked = command(["git", "-C", str(ff_repo), "ls-files"]).splitlines()
    ff["tracked_code_sha256"] = {}
    for name in tracked:
        path = ff_repo / name
        if path.suffix in (".py", ".txt", ".md", ".patch") or path.name == "Dockerfile":
            with path.open("rb") as stream:
                ff["tracked_code_sha256"][name] = hashlib.file_digest(stream, "sha256").hexdigest()
    # Working lists were rewritten by historical inference. Use committed lists
    # only as upstream evidence, not as an authenticated checkpoint manifest.
    ff["upstream_committed_split_lists"] = {
        split: command(["git", "-C", str(ff_repo), "show",
                        f"HEAD:data/ForAINetV2/meta_data/{split}_list.txt"]).splitlines()
        for split in ("train", "val", "test")}
    images = {name: command(["docker", "image", "inspect", tag, "--format", "{{.Id}}"])
              for name, tag in (("segmentanytree", "sat-sm120-test"), ("forestformer3d", "ff3d-sm120"))}
    sat_path = "/opt/segment-any-tree/model_file/PointGroup-PAPER.pt"
    code = inspect.getsource(inspect_checkpoint) + "\nimport json\nprint(json.dumps(inspect_checkpoint(" + repr(sat_path) + ")))"
    sat = json.loads(docker_read(images["segmentanytree"], ["python3", "-c", code]))
    if sat["sha256"] != SAT_SHA256:
        raise ValueError("Installed SegmentAnyTree weights differ from pinned upstream LFS")
    commit = docker_read(images["segmentanytree"],
                         ["git", "-C", "/opt/segment-any-tree", "rev-parse", "HEAD"])
    if commit != SAT_COMMIT:
        raise ValueError("SegmentAnyTree image source differs from the pinned commit")
    sat.update(checkpoint=sat_path, source_commit=commit,
        upstream_pointer=f"https://github.com/SmartForest-no/SegmentAnyTree/blob/{SAT_COMMIT}/model_file/PointGroup-PAPER.pt",
        documented_training_dataset="TreeinsFusedDataset; sparse_1000_500_100_10 path in checkpoint")
    with Path(__file__).open("rb") as stream:
        code_sha256 = hashlib.file_digest(stream, "sha256").hexdigest()
    return dict(schema_version=1, gpu_root=str(gpu_root), code_sha256=code_sha256,
                images=images, segmentanytree=sat, forestformer3d=ff,
                checkpoint_identity_verified=True, exhaustive_training_plot_manifest_available=False,
                FGI_EMIT_training_overlap="unknown", inference_run=False, evaluation_admitted=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gpu-root", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if not args.verify and args.out.exists():
        raise ValueError("Preserve the existing provenance receipt")
    receipt = collect(args.gpu_root.resolve(strict=True))
    if args.verify:
        if json.loads(args.out.read_text()) != receipt:
            raise ValueError("Checkpoint, image, code or source provenance changed")
        print("Installed candidate checkpoint provenance verified")
    else:
        with args.out.open("x") as stream:
            stream.write(json.dumps(receipt, indent=2) + "\n")
        print("Both checkpoints match official upstream weights; plot-level overlap remains unknown")


if __name__ == "__main__":
    main()
