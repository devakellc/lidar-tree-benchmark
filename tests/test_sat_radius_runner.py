"""Regressions for gpu/run_sat_radius_check.sh, run against a stand-in docker.

The stand-in keeps each container as a folder and plays a scripted outcome
(STUB_MODE), so the runner's checks run without Docker or a GPU: the exit
status, the logged radius, the rename of verified outputs only, resume, the
discarded leftovers, the timeout and unknown job names.

From the repository root:

    python3 -m unittest discover -s tests -p 'test_sat_radius_runner.py'
"""
import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

RUNNER = Path(__file__).resolve().parents[1] / "gpu" / "run_sat_radius_check.sh"

STUB = r"""#!/usr/bin/env bash
# Stand-in docker: a container is a folder under $STUB_ROOT.
set -u
cmd=$1; shift
case "$cmd" in
  create)
    radius=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -e) radius=${2#SAT_CLUSTER_RADIUS=}; shift 2 ;;
        --gpus|--network) shift 2 ;;
        --*) shift ;;
        *) break ;;
      esac
    done
    id=c$$$RANDOM; mkdir -p "$STUB_ROOT/$id"; printf '%s' "$radius" > "$STUB_ROOT/$id/radius"
    echo "$id" ;;
  cp)
    src=$1; dst=$2
    if [[ $dst == *:* ]]; then
      id=${dst%%:*}; mkdir -p "$STUB_ROOT/$id/pilot"; cp -r "${src%/.}/." "$STUB_ROOT/$id/pilot/"
    else
      id=${src%%:*}; cp "$STUB_ROOT/$id${src#*:}" "$dst"
    fi ;;
  start)
    id=${*: -1}; radius=$(cat "$STUB_ROOT/$id/radius"); mode=${STUB_MODE:-ok}
    [ "$mode" = fail ] && { echo boom; exit 3; }
    [ "$mode" = hang ] && sleep 30
    [ -n "$radius" ] && [ "$mode" != nolog ] && echo "sat_compat: region_grow radius $radius m" >&2
    [ "$mode" = spurious ] && echo "sat_compat: region_grow radius 9.0000 m" >&2
    mkdir -p "$STUB_ROOT/$id/pilot/out"; echo las > "$STUB_ROOT/$id/pilot/out/clip.las" ;;
  rm)
    rm -rf "$STUB_ROOT/${*: -1}" ;;
esac
"""


class Runner(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        bin_dir = self.tmp / "bin"; bin_dir.mkdir()
        stub = bin_dir / "docker"; stub.write_text(STUB)
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        self.root = self.tmp / "containers"; self.root.mkdir()
        self.out = self.tmp / "out"; (self.out / "in").mkdir(parents=True)
        ply = self.out / "in" / "clip.ply"; ply.write_text("ply")
        (self.out / "jobs.tsv").write_text(
            "job\tply\tradius\n"
            f"A_2__default\t{ply}\t\n"
            f"A_2__scaled\t{ply}\t1.0181\n")
        self.env = dict(os.environ, PATH=f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                        STUB_ROOT=str(self.root))

    def run_runner(self, *jobs, mode="ok", timeout="1800"):
        env = dict(self.env, STUB_MODE=mode, TIMEOUT=timeout)
        return subprocess.run(["bash", str(RUNNER), str(self.out), "2", *jobs],
                              env=env, capture_output=True, text=True, timeout=120)

    def outputs(self):
        return sorted(p.name for p in (self.out / "out").iterdir())

    def test_verified_jobs_are_renamed_and_the_run_succeeds(self):
        r = self.run_runner()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.outputs(), ["A_2__default.las", "A_2__scaled.las"])
        self.assertEqual(sorted(os.listdir(self.root)), [])   # containers removed
        self.assertIn("sat_compat: region_grow radius 1.0181 m",
                      (self.out / "logs" / "A_2__scaled.log").read_text())

    def test_a_failed_container_fails_the_run_and_keeps_no_output(self):
        r = self.run_runner(mode="fail")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("FAIL A_2__scaled rc=3", r.stdout)
        self.assertEqual(self.outputs(), [])

    def test_an_unlogged_radius_is_set_aside(self):
        r = self.run_runner("A_2__scaled", mode="nolog")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("override not logged", r.stdout)
        self.assertEqual(self.outputs(), ["A_2__scaled.las.unverified"])

    def test_an_override_on_a_default_job_is_set_aside(self):
        r = self.run_runner("A_2__default", mode="spurious")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("unexpected override", r.stdout)
        self.assertEqual(self.outputs(), ["A_2__default.las.unverified"])

    def test_resume_skips_verified_outputs_and_discards_leftovers(self):
        self.assertEqual(self.run_runner("A_2__default").returncode, 0)
        (self.out / "out" / "A_2__scaled.las.tmp").write_text("partial")
        r = self.run_runner()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("skip A_2__default", r.stdout)
        self.assertEqual(self.outputs(), ["A_2__default.las", "A_2__scaled.las"])
        r = self.run_runner(mode="fail")                      # nothing left to run
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_a_hung_container_times_out_and_is_removed(self):
        r = self.run_runner("A_2__scaled", mode="hang", timeout="1")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("FAIL A_2__scaled rc=124", r.stdout)
        self.assertEqual(self.outputs(), [])
        self.assertEqual(sorted(os.listdir(self.root)), [])

    def test_an_unknown_job_name_stops_before_any_run(self):
        r = self.run_runner("B_1__scaled")
        self.assertEqual(r.returncode, 1)
        self.assertIn("no job B_1__scaled", r.stderr)
        self.assertFalse((self.out / "out").exists() and self.outputs())


if __name__ == "__main__":
    unittest.main()
