# NEON Positional Evidence Follow-Up

This is a bounded, read-only investigation of the four unresolved individuals
in the [individual-reference comparison](../results/neon-individual-reference-results.md).
It prepares evidence for clarification, not a new reference policy or admission.

## Declared Checks

- Inspect released mapping records and measurement histories for HARV_033
  05646/05647, HARV_040 09167/09167A and BART_040 05808. Historical or later
  observations may explain status; they must not replace 2022 measurements.
  Do not interpret a latest-map table as a complete mapping change history.
- Inventory all archived named-point responses used by the predecessor support
  preparation. Report coordinate source, datum label and uncertainty. A receiver
  model, activation interval or generic WGS84 label does not establish a survey
  epoch, realization or absolute field-to-AOP alignment accuracy.
- For the two HARV_033 discrepancies only, compare the unchanged published
  UTM-offset recipe with a true-north ellipsoidal offset hypothesis. Use the
  existing `sf`/PROJ azimuthal-equidistant implementation with WGS84, centered
  on the anchor transformed from its unrounded UTM coordinates. Do not start
  from the API's rounded latitude/longitude. Report coordinate differences and
  both distances to the same recorded-subplot polygon and unchanged margin.
  Neither calculation is selected as a correction, even if one includes a tree.
- Extract the start/end GPS-week times from the four already archived HARV
  trajectory QA reports. Compare them with the archived point-time range and
  schedule candidate. Require unique parseable values within one GPS week.
  Containment corroborates a mission interval, not a flightline or source-ID
  crosswalk. Do not infer exact attribution or admit support from this check.

The convention comparison addresses an ambiguity between the
[field protocol, revision K](https://data.neonscience.org/api/v0/documents/NEON.DOC.000987vK)
and the [vegetation guide](https://data.neonscience.org/api/v0/documents/NEON_vegStructure_userGuide_vE.1).
It does not establish that either released data or the published recipe is
wrong. The ellipsoidal hypothesis uses the documented
[PROJ azimuthal-equidistant projection](https://proj.org/en/stable/operations/projections/aeqd.html).

## Inputs and Stop Rule

The source root contains pinned `reference_support_v2`,
`individual_reference_v2`, `reference_resolution_v2` and
`reference_resolution_evidence_v2` snapshots, plus the original field RDS files.
Verify their input/output receipts and hash inputs, code, this protocol and
software identity. Write outputs to a separate directory and verify replay.
PDF extraction requires the existing `pdftotext` command; no new R dependency
is installed. No cloud/raster download, detector run or BART spatial inspection
is part of this follow-up.

Once these checks finish, prepare exact source identifiers and questions for
NEON. Missing authoritative evidence remains unresolved; do not repeatedly
download the same metadata, borrow neighboring uncertainty, tune boundaries or
invent datum corrections. The inquiry remains a draft until actually submitted.
Preserve all original rows, geometries, support identities, selections and
admission blockers. Independent synthetic pipeline work can proceed while
external clarification is pending; real evaluation cannot.
