# Frozen FGI-EMIT reserve execution

Execute the original nine cells from the
[sealed input contract](fgiemit-reserve-input-protocol.md) in a fresh sibling
directory. The reserve runner replays all parents and binds the new execution
code before the first cell. It changes no policy, checkpoint, input support,
filter, matching rule or calibration setting.

The explicit-input cell adapter retains the admitted development algorithms.
It changes only data paths and owned container names. CHM uses the pinned
lasR runtime. SAT and FF3D use the existing immutable images and checkpoints.
Only annotation-free geometry, model scratch and adapter code enter model
containers. Reference files stay on the host for scoring.

Cells execute sequentially in the sealed order, with one attempt and a
3,600-second detector limit. Host scoring has its existing 600-second limit.
The first failure stops expansion. Failure and missing cells never become
zero predictions, and no fallback, thinning, retry or parameter rescue occurs.
Interrupted output is preserved and cannot be resumed as a new attempt.

Every accepted cell records execution status, source identities, resources,
prediction counts and separate primary apex/mask metrics plus fixed height
diagnostics. Replay checks exact file hashes, count arithmetic, category
denominators, ordered states and the unchanged input contract. Whole-row
instance identity and background checks happen before any output is admitted.

The three-plot primary summary requires every declared cell. Pool counts and
mask accumulators, report per-plot results, and keep height diagnostics
separate. Do not bootstrap these three plots into a primary uncertainty claim.
The selected FF3D policy does not change in response to reserve scores.

~~~sh
PYTHON="/path/to/original/checkout/gpu/.venv/bin/python"
ROOT="$CLAUDE_JOB_DIR/external/fgiemit"
PREPARED="$CLAUDE_JOB_DIR/fgiemit-reserve-v1"
RUN="$CLAUDE_JOB_DIR/fgiemit-reserve-run-v1"
"$PYTHON" scripts/run_fgiemit_reserve.py --root "$ROOT" \
  --prepared "$PREPARED" --out "$RUN"
"$PYTHON" scripts/run_fgiemit_reserve.py --root "$ROOT" \
  --prepared "$PREPARED" --out "$RUN" --verify
~~~

The original sources and all development artifacts remain unchanged. The
prospective claim stays conditional within-dataset policy evaluation:
upstream checkpoint overlap and independent AGL accuracy remain unknown.
Reserve evaluation does not admit a new fusion policy or sparse-density rule.
