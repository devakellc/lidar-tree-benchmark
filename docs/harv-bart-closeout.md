# HARV/BART Expansion Closeout

## Decision

The HARV/BART eastern-forest expansion was abandoned on 2026-09-18 at the
maintainer's request. This is a scope decision, not successful validation or
resolution of the reference-position and flight-provenance questions.
The broader benchmark and detection meta-pipeline remain active.

No further HARV/BART acquisition, positional investigation, NEON inquiry,
calibration, pilot scoring or held-out evaluation is planned. The prepared
inquiry remains unsent. No replacement validation site has been selected.

## Retained Evidence and Safeguards

- Keep the completed [preflight](../results/eastern-broadleaf-results.md),
  [support audit](../results/neon-reference-support-results.md),
  [record-resolution audit](../results/neon-reference-resolution-results.md)
  and [individual comparison](../results/neon-individual-reference-results.md)
  as historical diagnostic evidence. Their reproduction commands are not an
  active work order.
- Preserve existing data, artifacts, branches and prior results. The unmerged
  positional follow-up is not part of the mainline implementation. No code or
  data is deleted or reverted as part of this closeout.
- Keep the merged CRS, cache, event-specific support and reference-policy
  safeguards. All prepared eastern support remains diagnostic-only; closing
  the work does not clear admission flags or make nominal boxes fully censused.
- Do not claim HARV/BART detection performance or eastern-forest validation.
  No eastern detector comparison, calibration fit or eligible split was made.
- Keep historical NEON reference limitations and already observed external
  test results labelled. Abandoning these sites does not repair other reference
  populations or turn previously observed test data into a fresh holdout.

## Continuing Work

The next implementation is synthetic detection-only pipeline contracts:
explicit arms, per-cell outputs, missing/failed/completed-empty states, density
and score/mask provenance, and compatibility guards. It does not require
HARV/BART or a response from NEON and does not establish detector performance.

Before any new real-data comparison, separately declare suitable development
data, eligible reference support, whole-plot folds and held-out evaluation.
Do not silently substitute another site or tune on the observed external test
set. Controlled arm comparisons, fresh compatible calibration and evidence of
incremental fusion benefit remain necessary; crown validation remains separate.
