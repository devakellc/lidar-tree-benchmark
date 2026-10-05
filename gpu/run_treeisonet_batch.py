#!/usr/bin/env python3
# Runs many TreeisoNet cells in ONE process, so CUDA is initialised once per
# batch instead of twice per cell. Long runs that start and stop a GPU process
# every few seconds have hung the workstation; a site per process does not
# churn the GPU.
#
# Usage: run_treeisonet_batch.py <jobs.json>
# jobs.json is a list of objects, each one call of the existing drivers:
#   {"kind": "apex", "input": ..., "output": ..., "loc_pth": ..., "loc_cfg": ...,
#    "voxel": "0", "conf": 0.22}
#   {"kind": "crowns", "input": ..., "output": ..., "loc_pth": ..., "loc_cfg": ...,
#    "off_pth": ..., "off_cfg": ..., "voxel": "0", "conf": 0.22, "hmin": 2.0,
#    "aligned_out": ...}
# A job that fails leaves no output and writes <output>.error with the reason;
# the batch continues. Exit status is 0 unless the job list cannot be read.
import json, os, sys, time, traceback
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from run_treeisonet import apex
from run_treeisonet_crowns import crowns

def run(job):
    kind = job.get("kind")
    if kind == "apex":
        return apex(job["input"], job["output"], job["loc_pth"], job["loc_cfg"],
                    voxel=job.get("voxel", "0"), conf=job.get("conf", 0.5))
    if kind == "crowns":
        return crowns(job["input"], job["output"], job["loc_pth"], job["loc_cfg"],
                      job["off_pth"], job["off_cfg"], voxel=job.get("voxel", "0"),
                      conf=job.get("conf", 0.22), hmin=job.get("hmin", 2.0),
                      aligned_out=job.get("aligned_out"))
    raise ValueError(f"unknown job kind: {kind!r}")

def main(path):
    with open(path) as stream:
        jobs = json.load(stream)
    ok = 0
    for i, job in enumerate(jobs, 1):
        out = job.get("output", "")
        for stale in (out, out + ".error", job.get("aligned_out") or ""):
            if stale and os.path.exists(stale):
                os.remove(stale)                          # never leave a stale result
        t0 = time.time()
        try:
            run(job)
            ok += 1
            status = "ok"
        except BaseException as e:                        # SystemExit from the drivers too
            if isinstance(e, KeyboardInterrupt):
                raise
            for partial in (out, job.get("aligned_out") or ""):
                if partial and os.path.exists(partial):
                    os.remove(partial)
            with open(out + ".error", "w") as stream:
                stream.write("".join(traceback.format_exception_only(type(e), e)))
            status = f"failed: {e}"
        print(f"[{i}/{len(jobs)}] {job.get('kind')} {os.path.basename(job.get('input', ''))} "
              f"{status} ({time.time() - t0:.1f}s)", flush=True)
    print(f"batch done: {ok}/{len(jobs)} jobs ok", flush=True)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: run_treeisonet_batch.py <jobs.json>")
    main(sys.argv[1])
