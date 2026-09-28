"""Bounded process execution with independent container and local cleanup."""
import os
from pathlib import Path
import signal
import subprocess
import time

from run_fgiemit_pilot import write_json

REPO = Path(__file__).resolve().parents[1]


def bounded(command, directory, env=None, container=None, timeout=3600):
    """Preserve the original failure even if Docker or local cleanup fails."""
    write_json(directory / "command.json", dict(argv=command, timeout_seconds=timeout))
    started = time.monotonic()
    with (directory / "inference.log").open("w") as log:
        proc = subprocess.Popen(command, cwd=REPO, env=env, stdout=log,
                                stderr=subprocess.STDOUT, start_new_session=True)
        try:
            status = proc.wait(timeout=timeout)
            elapsed = time.monotonic() - started
            write_json(directory / "execution.json", dict(exit_code=status, wall_seconds=elapsed))
            if status:
                raise RuntimeError(f"Detector exited with status {status}; see inference.log")
        except BaseException:
            cleanup_errors = []
            try:
                if container:
                    subprocess.run(["docker", "rm", "-f", container],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                        timeout=30, check=True)
            except BaseException as error:
                cleanup_errors.append(f"Container cleanup failed: {type(error).__name__}: {error}")
            finally:
                # Docker failure must never bypass killing and reaping the host
                # process group (including children of wrappers such as time).
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                except BaseException as error:
                    cleanup_errors.append(f"Process group cleanup failed: {type(error).__name__}: {error}")
                try:
                    proc.wait(timeout=30)
                except BaseException as error:
                    cleanup_errors.append(f"Process reap failed: {type(error).__name__}: {error}")
            # Diagnostics cannot replace the original detector failure.
            try:
                for error in cleanup_errors:
                    log.write(error + "\n")
                log.flush()
            except Exception:
                pass
            raise
    return elapsed
