# TEAK candidate reference reconstruction

This declaration covers the seven distributed TEAK plots identified by the
[metadata audit](../results/teak-validation-audit.md): TEAK_004, TEAK_005,
TEAK_010, TEAK_016, TEAK_018, TEAK_024 and TEAK_025, using exact 2022 census
events from the cached RELEASE-2026 vegetation-structure tables.

The purpose is to reconstruct diagnostic field support before detector
comparison. No plot is admitted to calibration or evaluation by this step.
No detector output is inspected, no model is run and no split is selected.
Existing benchmark clouds, reference tables, predictions and metrics remain
protected. The [retired eastern study](harv-bart-closeout.md) stays retired.

## Reference and mapping policy

Reuse the existing mapped-bole policy: live single-bole and multi-bole tree
records with measured DBH at least 10 cm. Preserve every exact-year record
and explicit exclusions. Finite positive height and unambiguous mapped
coordinates are required for a diagnostic selected reference. Missing height
remains missing; do not borrow another bole's height or a different year's
measurement. Related identifiers are not silently collapsed into one tree.

Join census metadata on plot and event, then retain each measurement date.
Use the latest unambiguous released mapping, retaining its date and source
record identity. Export mapping and measurement histories for review; a
mapping later than the event date is a timing diagnostic, not proof that the
tree moved. Distinguish event, individual measurement and mapping dates.
Contributing flight dates remain a separate unresolved acquisition question.

The two plots with zero target records remain in scope. Report other growth
forms; zero target boles does not establish no trees, no vegetation or a valid
all-tree negative control. Bole-relative detection cannot validate crowns,
all-tree precision, instance masks, biomass or species accuracy.

## Measured support

Fetch the public NEON location records for every sampled-subplot corner and
mapped anchor needed by the selected exact-year records. Preserve full JSON
responses, URL, retrieval time, HTTP status and content hash. Read the field
CRS from metadata, require named-point identity and matching metric frame,
and retain coordinate uncertainty. Do not synthesize missing points.

Request `?history=true` and verify the exact request URL and raw response
SHA-256 before parsing coordinates. Ignore any separately cached parsed
`data` object. Select coordinates and properties only from `locationHistory`,
never from the current top-level coordinate fields. Require exactly one
interval covering the entire 2022 census-event date. For mapped anchors,
also require coverage for each individual measurement and retained mapping
date. Dates have day resolution; an interval transition within a required
day is ambiguous. Treat intervals as start-inclusive and end-exclusive;
a missing end is accepted only for a record marked current.

All selected intervals for a named point must agree exactly on coordinates,
metric frame and uncertainty. Differing epochs, missing history and
overlapping intervals exclude that point explicitly; the diagnostic does
not infer movement or choose an epoch silently. Retain required dates and
selected history indices and validity bounds in `named_points.csv`. This
conservative policy allows the shared geometry helper to use one unambiguous
coordinate per named point, while preserving field-to-cloud datum review.

Construct surveyed subplot quadrilaterals using the existing support helpers.
Reject missing corners, unsupported encodings, overlapping or invalid
geometries and incomplete census scope. Report nominal and measured area
separately. Retain both the complete measured footprint and an explicitly
labelled conservative interior eroded by the maximum recorded corner/target
position uncertainty plus the existing 0.6 m rangefinder allowance. This is
a diagnostic boundary policy, not a calibrated confidence interval.

Expose references outside their recorded subplot, outside the sampled
footprint, near the boundary, or excluded for height/mapping/quality reasons.
Preserve geometry failures as explicit per-plot failures; do not shrink the
seven-plot declaration to whichever plots happen to build successfully.
For failed geometry, eligibility remains a pre-geometry count while selected
counts and geometry-dependent reference flags remain unknown (`NA`).

## Admission and reproducibility

All bundles have `evaluation_ready = FALSE` and unresolved field-to-cloud
datum, contributing-flight, density/coverage and checkpoint-exposure gates.
Missing target records, unresolved geometry or measurement-subplot conflicts
add further blockers. No flag in this workflow enables scoring.

Bind preparation to the audited parent receipt and unchanged field input.
Verify parent input/output hashes before reading, retain parent identity and
hash each source before use, then verify sources again before completion.
Record code and package identities, output hashes and all seven plot statuses.
Use a fresh output directory. `FETCH=1` permits public location metadata
retrieval only; a supplied `LOCATIONS=` archive supports offline reproduction.
A failed or missing HTTP record remains explicit and does not become a point
at a default coordinate. Preserve failed attempts as evidence.
