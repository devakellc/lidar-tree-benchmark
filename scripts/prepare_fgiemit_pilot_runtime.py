#!/usr/bin/env python3
"""Build the pinned lasR pre-devel source into a separate pilot-only library."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tarfile

from audit_fgiemit_development import file_hash

REVISION = "97dd5fb85fada7de0dbd024246751a9941daedaf"
UPSTREAM = "https://github.com/r-lidar/lasR"


def environment(out):
    env = dict(os.environ)
    # Keep the normal libraries available for unchanged dependencies.
    env["R_LIBS"] = str(out / "library")
    return env


def identities(out):
    package = out / "library/lasR"
    return {str(p.relative_to(out)): file_hash(p) for p in sorted(package.rglob("*"))
            if p.is_file()}


def probe(out):
    code = '''p <- find.package("lasR")
x <- lasR::local_maximum_raster(lasR::rasterize(.25, "max"),
    function(h) pmin(pmax(.1*h+3,3),5))
cat(jsonlite::toJSON(list(path=p, version=as.character(packageVersion("lasR")),
    variable_window_constructor=TRUE),auto_unbox=TRUE))'''
    result = json.loads(subprocess.check_output(["Rscript", "-e", code],
        env=environment(out), text=True, timeout=60))
    if Path(result["path"]).resolve() != out / "library/lasR":
        raise ValueError("Pilot did not load the isolated lasR library")
    return result


def verify(out):
    receipt = json.loads((out / "runtime.json").read_text())
    if (receipt["revision"] != REVISION or receipt["upstream"] != UPSTREAM or
            receipt["archive_sha256"] != file_hash(out / "source.tar") or
            receipt["installed_sha256"] != identities(out) or
            receipt["probe"] != probe(out) or
            receipt["builder_sha256"] != file_hash(Path(__file__))):
        raise ValueError("Pinned pilot runtime changed")
    return receipt


def build(repo, out):
    if out.exists():
        raise ValueError("Use a new runtime directory; preserve previous builds")
    revision = subprocess.check_output(["git", "-C", str(repo), "rev-parse",
                                       REVISION + "^{commit}"], text=True).strip()
    if revision != REVISION:
        raise ValueError("Pinned pre-devel revision unavailable")
    out.mkdir(parents=True)
    archive = out / "source.tar"
    subprocess.run(["git", "-C", str(repo), "archive", "--format=tar",
                    "--output=" + str(archive), REVISION], check=True)
    source, library = out / "source", out / "library"
    source.mkdir(); library.mkdir()
    with tarfile.open(archive) as stream:
        stream.extractall(source, filter="data")
    env = environment(out); env["MAKEFLAGS"] = "-j4"
    command = ["R", "CMD", "INSTALL", "--no-multiarch", "-l", str(library), str(source)]
    with (out / "build.log").open("w") as log:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, env=env,
                       check=True, timeout=1200)
    receipt = dict(upstream=UPSTREAM, branch="pre-devel", revision=REVISION,
        branch_resolved_on="2026-09-23", archive_sha256=file_hash(archive),
        builder_sha256=file_hash(Path(__file__)), command=command,
        installed_sha256=identities(out), probe=probe(out))
    (out / "runtime.json").write_text(json.dumps(receipt, indent=2) + "\n")
    verify(out)
    print("Verified isolated lasR pre-devel runtime:", REVISION)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lasr-repo", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if args.verify:
        verify(args.out.resolve())
    elif args.lasr_repo is None:
        parser.error("--lasr-repo is required when building")
    else:
        build(args.lasr_repo.resolve(strict=True), args.out.resolve())
