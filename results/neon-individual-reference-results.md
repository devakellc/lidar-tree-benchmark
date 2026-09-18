# NEON Individual-Level Reference Comparison

## Decision

The 2026-09-18 field-only comparison implements the predeclared
[individual-level policy](../docs/neon-individual-reference-protocol.md).
It produces **206 HARV and 226 BART diagnostic interior references**, compared
with the unchanged bole-level baseline of 204 and 226. Every previously
selected apparent individual remains represented. Two additional HARV
individuals now have an explicitly sourced height under the new policy.

**No support is evaluation-ready.** Four target individuals remain unresolved,
and field-marker, flight-provenance, physical-coverage and density gates remain.
No detector, calibration, historical rescore or split freeze ran. No imagery,
point clouds or new metadata were downloaded; BART remains spatially uninspected.

The later [positional follow-up](neon-positional-evidence-results.md) quantifies
a coordinate-convention hypothesis and prepares an unsent evidence request.
It leaves this policy, its selections and all admission blockers unchanged.

## Policy Applied

One apparent individual is formed per documented permanent bole family within
the same plot and census event. At least one living tree bole must have measured
DBH of 10 cm or greater. The derived row records its qualifying boles, primary
location source, separate height source and every unresolved reason.

The [NEON vegetation guide, sections 6.2-6.3](https://data.neonscience.org/api/v0/documents/NEON_vegStructure_userGuide_vE.1)
describes related bole IDs and individual-level height/crown measurements.
This benchmark interpretation accepts the living primary's mapped position.
A living broken primary with missing height may use its unique intact,
height-bearing relative. It does not substitute break height, infer a location
from a dead primary, or choose between multiple height measurements.

The unit is an apparent individual, not an independently located bole, canopy
component or crown polygon. These are field-reference counts, not detection
performance or crown-instance validation. Selecting source measurements for a
new individual row never fills or rewrites the original bole records.

## Paired Field Comparison

Both policies use exactly the same measured footprints, uncertainty interiors,
subplot polygons and positional margins. No geometry was enlarged or re-eroded.

| Quantity | HARV | BART |
| --- | ---: | ---: |
| Original field rows retained in crosswalk | 634 | 635 |
| Original target bole rows | 274 | 276 |
| Target apparent individuals | 247 | 264 |
| Unresolved target individuals | 3 | 1 |
| Policy-complete individuals before interior filtering | 244 | 263 |
| Original selected bole rows | 204 | 226 |
| Selected diagnostic individuals | 206 | 226 |
| Previously selected individuals retained | 204 | 226 |
| Newly selected individuals | 2 | 0 |
| Previously selected individuals lost | 0 | 0 |

The 550 target bole rows become 511 target apparent individuals. This is a
change of reference unit, not the discovery or removal of 39 physical trees.
No family contains multiple originally selected boles in this actual snapshot;
the regression suite separately covers that case. No candidate tree group has
undetermined population membership under this policy.

| Plot | Original selected boles | New diagnostic individuals | Unresolved target individuals |
| --- | ---: | ---: | ---: |
| HARV_033 | 30 | 30 | 2 |
| HARV_034 | 55 | 55 | 0 |
| HARV_038 | 52 | 52 | 0 |
| HARV_039 | 37 | 37 | 0 |
| HARV_040 | 30 | 32 | 1 |
| BART_036 | 45 | 45 | 0 |
| BART_040 | 36 | 36 | 1 |
| BART_042 | 49 | 49 | 0 |
| BART_071 | 41 | 41 | 0 |
| BART_073 | 55 | 55 | 0 |

Three living broken-primary families use a relative's recorded height:

| Plot | Primary ID suffix | Height source suffix | Height, m | Source DBH, cm | Selection change |
| --- | --- | --- | ---: | ---: | --- |
| HARV_038 | 05731 | 05731A | 8.7 | 12.9 | Already represented by the secondary bole |
| HARV_040 | 09206 | 09206A | 11.7 | 8.2 | New diagnostic individual |
| HARV_040 | 09212 | 09212A | 6.9 | 7.1 | New diagnostic individual |

The latter two height donors are below the old per-bole DBH threshold. They
provide height evidence for a qualifying individual; they are not themselves
new target boles. Full identities, measurement UIDs, mapping UIDs and dates are
exported. Primary coordinates remain mapped-stem positions, not measured apices.

## Unresolved Individuals and Admission

- HARV_033 05646 and 05647 retain their marginal recorded-subplot conflicts.
  The earlier distances and margins remain unchanged; no offset convention or
  uncertainty threshold was adjusted to include them.
- HARV_040 09167 has a dead primary and living secondary 09167A. Its individual
  is in the target population, but the policy does not borrow the dead primary's
  coordinates. An authoritative living-individual location decision is needed.
- BART_040 05808 still lacks coordinate uncertainty for named point 51. A known
  height does not repair this missing positional evidence.

Each new bundle preserves all predecessor blockers as inherited evidence and
adds explicit individual-policy, physical-coverage and native-density review
gates. Inherited bole-completeness flags are historical audit findings, not a
claim that the new table has the same number of unresolved individuals. They
are not silently cleared. The scorer rejects every real bundle, and pooling
rejects mixtures of individual-level and bole-level populations.

Next, review the declared policy and resolve the four cases above alongside
field-marker realization/epoch/accuracy and the missing point-to-flight
crosswalk described in the [provenance audit](neon-reference-resolution-results.md).
Only after remaining score-blind physical coverage and density checks can a
separate admission decision permit a bounded HARV comparison. BART remains
reserved for evaluation of a frozen pipeline.

## Reproduction and Verification

Use the already pinned field and support snapshots in separate input roots:

```sh
export CLAUDE_JOB_DIR=/home/alex/projects/lidar_tree_benchmarks/work/eastern-reference-support-2022
Rscript scripts/prepare_neon_individual_references.R \
  SOURCE="$CLAUDE_JOB_DIR" \
  SUPPORT="$CLAUDE_JOB_DIR/reference_support_v2" \
  OUT="$CLAUDE_JOB_DIR/individual_reference_v2"
Rscript tests/run_tests.R
rumdl check --no-cache .
git diff --check
```

The output directory contains `individual_references.csv`,
`source_crosswalk.csv`, `policy_comparison.csv`, diagnostic support bundles,
input/output receipts and an integrity summary. Replay is offline and rejects
changed inputs, policy contracts or output content. The earlier exploratory
output directory is preserved separately.

All **97 protected input/code/policy hashes** remain unchanged. The crosswalk
retains all 1,269 original field rows without changing their source values.
Regression tests cover family identity, donor ambiguity, dead/broken primaries,
below-threshold height donors, unknown uncertainty, hidden spatial conflicts,
unchanged geometry, unique denominators, scoring/pooling guards, offline replay
and tamper rejection. The full R suite passes with three existing skips and
the optional R-universe package-index warning.
