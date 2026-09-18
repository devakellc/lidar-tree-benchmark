# NEON Individual-Level Reference Policy

**Archived after the 2026-09-18 [HARV/BART closeout](harv-bart-closeout.md).**
The declarations below document the retired study, not authorization to resume
it. Existing safeguards and diagnostic-only status remain unchanged.

## Scope

This declares `individual_reference_v1` before its field-data comparison.
It derives a separate diagnostic reference table from the pinned
[bole-level support](neon-reference-support-protocol.md), informed by the
[record-resolution audit](../results/neon-reference-resolution-results.md).
Original rows, selected references, geometries and support identities remain
unchanged. This policy does not admit evaluation or change historical scores.

The unit is an apparent individual, not a bole, detected apex or delineated
crown. A multi-bole individual may have multiple canopy components. Therefore
one reference per individual does not define a crown-instance ground truth.

## Population and Identity

An individual qualifies when at least one living `single bole tree` or
`multi-bole tree` record has measured DBH at least 10 cm in the exact census
event. Do not sum diameters, apply basal-area equivalents, or use a dead bole
to satisfy the threshold. Retain smaller and dead relatives as evidence.
Missing status or an invalid live-bole diameter leaves population membership
undetermined when no qualifying live bole is established.

Join only within the same plot and event. For permanent multi-bole IDs, the
documented single trailing letter identifies a related bole. Require a unique
unsuffixed primary, matching tree growth forms, matching site identifiers and
one common sampled subplot. Reject duplicate IDs, unsupported IDs, conflicting
growth forms, source quality flags and ambiguous latest mapping records.
Do not use liana-support fields or cross-year relatives to construct families.
Non-tree groups stay outside the population and remain in the source crosswalk.

The [vegetation guide, sections 6.2-6.3](https://data.neonscience.org/api/v0/documents/NEON_vegStructure_userGuide_vE.1)
describes bole identifiers and individual-level measurements. The event's
[field protocol, revision K](https://data.neonscience.org/api/v0/documents/NEON.DOC.000987vK)
documents mapping and broken-bole measurements. The rules below are an explicit
benchmark interpretation, not a claim that every family is fully observed.

## Location and Height

Use only the living unsuffixed primary's existing mapped coordinates and
uncertainty, preserving the exact measurement and latest-mapping row IDs.
Require a `map and tag` record, finite coordinates, the bundle's metric CRS
and finite positional uncertainty. A dead, absent or ambiguous primary is not
a location donor, even if a living secondary has height. Do not choose another
bole because its location fits the polygon better. Retain mapping dates even
when they postdate the census; this preserves the existing latest-map policy,
not an independently verified census-date location.

Accept a finite positive primary height when it is the only recorded positive
height among living family members. For a living broken primary with missing
height and a recorded positive break height, allow the unique living, unbroken
height-bearing relative as the individual-level height source, including a
relative below 10 cm DBH. Require that relative's recorded height; do not use
break height, a mean, maximum, model prediction or a value from another event.
Multiple height-bearing rows remain ambiguous even if their values agree.
Invalid recorded live heights and nonblank height qualifiers require review.

Carry canopy class from the chosen height record, with its source ID. Export
the location and height source identities separately: selecting measurements
for a new individual-level row is not filling another bole's source record.
Unknown canopy class remains unknown and does not authorize class imputation.

## Fixed-Support Comparison

Reuse the exact predecessor footprint, interior, subplot polygons and margin.
Do not re-erode the support after combining rows. Test the primary location
against its recorded subplot and uncertainty even when its old height was
missing; an earlier first-exclusion label must not hide a spatial discrepancy.
Any already recorded family subplot conflict remains a review blocker.

Export all source-to-unit links, original eligibility/selection, qualifying
boles, location/height donors, every unresolved reason and new diagnostic
selection. Compare unique individuals separately from original selected bole
rows, including groups with multiple previously selected boles and newly
height-resolved groups. Neither count is a detector score or a frozen split.

## Integrity and Admission

Require pinned predecessor input/output receipts. Hash inputs, implementation,
software and this policy; verify them and output receipts on replay. Output
must be a new directory outside the predecessor snapshots. Reject tampering
and changed policy contracts rather than replacing existing artifacts.

New support has a distinct population, policy and identity. Preserve all
predecessor blockers as inherited evidence, plus explicit individual-policy,
physical-coverage and native-density review gates. Even a complete individual
row is diagnostic only. Scoring and mixed-population pooling must reject it.
Do not run detectors, fit calibration, inspect BART spatial data or freeze an
eligible split. Positional uncertainty, field-marker provenance, marginal
subplot disagreements and flight attribution require separate decisions.
