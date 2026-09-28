# Native FGI-EMIT pipeline: current execution and replay

The versioned entry point retains the frozen scientific algorithms, policy,
inputs and historical results. It adds reliable local process cleanup,
contract-scoped attempt admission, product-output admission before execution,
and explicit verification of requested run and method identities.

Use this entry point for current assembly. The
[original guide](final-ensemble-pipeline.md), original scripts and accepted
artifacts remain byte-identical for historical replay. The
[observed results](../results/final-ensemble-pipeline-results.md) describe those
original detector runs; the changes here neither rerun them nor retune methods.
The supported population and scientific limits remain unchanged.

## Reuse accepted inference

Run from the repository root with the existing Python environment. Choose a
fresh product directory; leave the accepted detector run in place.

~~~sh
export CLAUDE_JOB_DIR="/home/alex/projects/lidar_tree_benchmarks/work"
PYTHON="/home/alex/projects/lidar_tree_benchmarks/gpu/.venv/bin/python"
ROOT="$CLAUDE_JOB_DIR/external/fgiemit"
PREPARED="$CLAUDE_JOB_DIR/fgiemit-reserve-v1"
RUN="$CLAUDE_JOB_DIR/fgiemit-reserve-run-v1"
OUT="$CLAUDE_JOB_DIR/fgiemit-reserve-products-v2"
Rscript scripts/assemble_metapipeline_v2.R MODE=fgiemit \
  PYTHON="$PYTHON" ROOT="$ROOT" PREPARED="$PREPARED" RUN="$RUN" OUT="$OUT"
Rscript scripts/assemble_metapipeline_v2.R MODE=fgiemit \
  PYTHON="$PYTHON" ROOT="$ROOT" PREPARED="$PREPARED" RUN="$RUN" OUT="$OUT" \
  STAGE=reserve METHOD=selected_policy VERIFY=true
~~~

The same entry point accepts `STAGE=development` with an optional development
`METHOD`, using the methods documented in the original guide. It reuses sealed
predictions and calibration. Omit `PREPARED` and `RUN` in development mode;
its parents come from the frozen calibration receipt. Synthetic mode remains
available. Direct Python invocation uses `scripts/run_ensemble_pipeline_v2.py`
and lowercase flags.

During verification, explicitly supplied `PREPARED`, `RUN`, `STAGE` and `METHOD`
must match the product manifest. Omitted options impose no extra expectation;
full manifest and parent verification still runs. `VERIFY=true` cannot be
combined with `EXECUTE=true`. V1 receipts dispatch to the unchanged historical
verifier, while new products bind the v2 code and unchanged scientific files.

## Execution admission and failure handling

`EXECUTE=true` permits a missing reserve run only when the sealed input contract
has no prior attempt. It does not authorize repeating the completed reserve
study. The runner checks sibling run receipts for the same prepared inputs or
contract, including running, failed and incomplete attempts. It then atomically
creates a sibling `.fgiemit-reserve-attempt-<hash>` directory before creating a
new run. The claim binds the parent hashes and run path and remains after any
failure. Concurrent v2 callers cannot both claim the contract. Do not remove,
move or edit claims or old run directories to bypass this boundary.

The v2 receipt records its code hashes and attempt identity before the first
cell. Assembly captures its code hashes before optional inference and rejects
code changes during execution or product generation. Existing v1 runs are
read-only and need no retrospective claim. Original runners remain available
for historical verification; use v2 for current work. Attempt discovery covers
the contract's required sibling output location; manual relocation or
execution through archived scripts bypasses that guard and is outside this
workflow.

Before any optional inference, assembly creates its actual output directory
and writes `assembly_status.json`. An unavailable or unwritable sink therefore
fails before consuming a detector attempt. Later failures preserve that output
and record a failed status where writable. Completed products seal the status
file with all other output hashes. A failed assembly directory cannot be reused;
choose a fresh product directory and reuse the same accepted detector run.

On a detector timeout, interruption or nonzero exit, Docker cleanup remains
bounded to 30 seconds. Its timeout, missing executable or nonzero exit cannot
skip killing the local process group and reaping its leader. The original
detector exception is preserved, along with the exit receipt for a nonzero
exit; cleanup failures are recorded in `inference.log`. Failed Docker cleanup
does not prove the remote container stopped, so inspect the logged owned
container before subsequent GPU work. There is no automatic retry. The
existing 3,600-second detector and 600-second scoring limits remain.

## Verification coverage

The focused suite uses real local subprocesses, including descendants, with
mocked Docker failures. It checks cleanup, preserved exceptions, versioned
receipt identity, unchanged scientific functions, historical dispatch,
contract attempt exclusion, output admission and explicit verification options.
It does not execute detectors or establish new benchmark performance.

~~~sh
/home/alex/projects/lidar_tree_benchmarks/gpu/.venv/bin/python \
  -m unittest discover -s tests -p 'test_fgiemit_execution_v2.py'
Rscript tests/run_tests.R
rumdl check --no-cache .
git diff --check
~~~
