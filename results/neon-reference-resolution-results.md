# NEON Reference Resolution and Flight Provenance

## Decision

The 2026-09-18 follow-up explains **42 of the 43 original per-bole exclusions**
through individual-level measurement conventions. They are not 42 independently
missing trees. This corrects the interpretation of the earlier
[support audit](neon-reference-support-results.md), not its recorded outputs.

**No support is admitted for evaluation.** A new individual-level reference
policy, field positional evidence and remaining spatial checks are required.
Do not fill missing values or silently drop additional boles. No coordinates,
heights, boundaries, selected references or support identities were changed.
No detector, calibration or historical rescore ran.

The subsequent [individual-level comparison](neon-individual-reference-results.md)
now implements a declared policy in separate diagnostic outputs. It preserves
this audit and its source records; it does not admit evaluation.

## Record-Level Findings

Evidence joins use exact plot/event/identity and retain related records outside
the original live-DBH threshold. The 43 exclusions plus two subplot discrepancies
give 45 review rows.

| Explanation | HARV | BART | Decision |
| --- | --- | --- | --- |
| Additional bole with individual-level measurements on the primary record | 26 | 12 | Explained; not an independently located/height-measured tree |
| Broken primary with height recorded on a living relative | 3 | 0 | Preserve both records; do not substitute height or break height |
| Living, height-bearing secondary with a dead primary | 1 | 0 | Requires explicit tree-level location and status policy |
| Unknown named-point uncertainty | 0 | 1 | Unresolved source metadata |
| Position outside recorded subplot beyond the current margin | 2 | 0 | Unresolved boundary interpretation |
| Total reviewed records | 32 | 13 | No automatic admission |

The [vegetation guide, sections 6.2-6.3](https://data.neonscience.org/api/v0/documents/NEON_vegStructure_userGuide_vE.1)
documents trailing-letter bole relationships and individual-level height/crown
measurements. The event's
[field protocol, revision K](https://data.neonscience.org/api/v0/documents/NEON.DOC.000987vK),
Table 12 and SOP E.2.1, distinguishes mapping the principal bole from tagging
additional boles, and measurements for intact versus broken boles.
`supportingStemIndividualID` describes liana support, not a multi-bole link.

Thirty-five excluded records have `recordType="tag only"` and missing mapping
coordinates. Four other additional-bole records are mapped but lack independent
height. Copying primary measurements into multiple scored references would
not recover independently observed boles.

Three HARV primary boles are broken:

| Primary ID suffix | Break height, m | Height-bearing relative | Relative height, m | Relative DBH, cm |
| --- | --- | --- | --- | --- |
| 05731 | 4.6 | 05731A | 8.7 | 12.9 |
| 09206 | 10.0 | 09206A | 11.7 | 8.2 |
| 09212 | 5.3 | 09212A | 6.9 | 7.1 |

The last two relatives fall below the old per-bole DBH threshold. Filtering
them before examining the family would discard relevant measurement evidence.
Separately, HARV 09167 is dead/broken while 09167A is live, has height 14.5 m,
and lacks its own coordinates. No location was borrowed from its dead primary.
Full permanent IDs and source row identifiers are retained in CSVs.

HARV_033 records 05646 and 05647 lie **0.8606 m and 0.8306 m** from their
recorded subplot, compared with **0.79 m** positional margins. The excesses
are only 0.0706 m and 0.0406 m: marginal disagreements under the declared rule,
not proof of wrong field records. No boundary or offset convention was changed.

BART_040 record 05808 uses `BART_040.basePlot.vst.51`. A fresh public location
response still reports coordinate source `GIS` and generic WGS84, without
coordinate uncertainty. No neighboring-point uncertainty was imputed.

## Datum Evidence

The [official datum report, section 3.2](https://data.neonscience.org/api/v0/documents/NEON.DOC.002293vB)
explains the AOP convention: ITRF00 trajectories are treated as equivalent to
WGS84(G1150), while elevations reference Geoid12A. The archived HARV trajectory
QA reports also identify ITRF00. Thus the product wording and WGS84 headers are
not, by themselves, evidence of a CRS mistake.

This does not establish the realization, survey epoch or absolute accuracy of
each WGS84-labelled field marker. The datum report's historical vertical
correction was not applied to the current tile. Tree heights, field-marker
elevations and absolute LiDAR elevations remain different quantities.
Field-to-AOP positional reconciliation is still pending.

## HARV Flight Evidence

The collection retained four trajectory QA PDFs, 40 KML boundaries, 40 bounded
64 KiB header excerpts and the same previously selected HARV_033 classified
tile. No full flightline cloud was downloaded. BART remains field/named-point
metadata only, with no imagery or point-cloud inspection.

The [published flight schedule](https://www.neonscience.org/data-collection/flight-schedules-coverage)
lists HARV visit 7 on August 3, 4, 12 and 14, 2022. Six conservative flightline
enclosures intersect the sampled-footprint buffer: L001-1, L001-2, L001-3,
L007-1, L008-1 and L009-1. KML linework is noded into candidate enclosures;
filled interior holes mean these are not verified physical-coverage masks.

The separate 25 m buffer around measured support contains **72,866 points**,
all with Point Source ID 7 and GPS week time approximately 397530.4-397531.7 s.
This is not the earlier nominal-box clip or a new density benchmark. The LAS
header declares week time. The weekday is compatible with **August 4, 2022**,
the only published candidate on that weekday. The declared GPS-minus-UTC offset
for 2022 is 18 s; the audit preserves calendar-day ambiguity near midnight.

However, **all 40 source-flightline headers have File Source ID 0**. The
[LiDAR format description](https://data.neonscience.org/api/v0/documents/NEON.DOC.001292vB)
does not justify equating tile Point Source ID 7 with filename L007-1 without
the missing crosswalk. August 4 is a supported schedule/time candidate, not
independently verified point-to-flight attribution. Creation dates were not
used as acquisition dates. No withheld-point policy changed; the bounded LAS
read reports 170 withheld points before the exact buffer filter.

## Reproduction and Verification

Run from the implementation checkout. Source snapshots remain read-only;
outputs must be separate from protected input roots.

```sh
export CLAUDE_JOB_DIR=/home/alex/projects/lidar_tree_benchmarks/work/eastern-reference-support-2022
Rscript scripts/collect_neon_reference_evidence.R HARV_LIDAR=TRUE \
  OUT="$CLAUDE_JOB_DIR/reference_resolution_evidence_v2"
Rscript scripts/audit_neon_reference_resolution.R \
  SOURCE="$CLAUDE_JOB_DIR" \
  SUPPORT="$CLAUDE_JOB_DIR/reference_support_v2" \
  EVIDENCE="$CLAUDE_JOB_DIR/reference_resolution_evidence_v2" \
  OUT="$CLAUDE_JOB_DIR/reference_resolution_v2"
Rscript tests/run_tests.R
rumdl check --no-cache .
git diff --check
```

Outputs include `resolution_records.csv`, `resolution_members.csv`,
`resolution_plots.csv`, flight candidates, point-source/time evidence and
immutable input/output receipts. Public URLs are archived; signed download
URLs and tokens are not. Earlier exploratory outputs remain separate.

The actual run checked **192 input/evidence/code file hashes** before and after,
with no change. Existing selection remains 204 HARV and 226 BART diagnostic
references. Synthetic regressions cover exact family joins, broken/dead
primaries, below-threshold relatives, source preservation, boundary distances,
KML interiors, ambiguous times/IDs and tamper rejection. The full R suite passes
with three existing skips (live GPU, empty-LAS fixture, Python `plyfile`) and
the existing optional R-universe index warning.

## Following Decisions

1. Predeclare an individual-level reference policy with auditable bole links,
   unique denominators and explicit location/height selection. Do not interpret
   explained records as independently missing trees or clear old blockers.
2. Obtain uncertainty for BART_040 point 51 and clarify the marginal HARV_033
   subplot discrepancies, including offset/boundary conventions.
3. Resolve field-marker realization/epoch and the HARV point-to-flight
   crosswalk. Schedules and matching EPSG headers do not close those questions.
4. Finish physical coverage and per-plot density checks before admitting plots
   or freezing a split. Only then run a bounded HARV comparison; BART remains
   reserved for the frozen pipeline's held-out evaluation.
