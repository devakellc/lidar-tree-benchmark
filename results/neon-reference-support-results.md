# NEON Event-Specific Reference Support

## Status

The opt-in event/reference/geometry implementation and score-blind field audit
are complete. **No real support bundle is evaluation-ready.** Missing target
references, subplot inconsistencies and unresolved field/AOP datum and flight
provenance still prevent calibration, pilot scoring or eligible-split freezing.
No detector inference, fitting or historical rescore was performed.

This follows the [eastern preflight](eastern-broadleaf-results.md) under the
[reference-support protocol](../docs/neon-reference-support-protocol.md).
HARV is development; BART remains held out. This run inspected BART field and
named-point metadata only, not BART LiDAR, RGB or detector performance.

## Preparation

The run on **2026-09-18** used exact-2022 measurements from `RELEASE-2026`.
The earlier temporary eastern worktree and generated data no longer existed.
Field data and the single predeclared HARV RGB tile were regenerated in a
persistent, separate job directory; historical California and external data
were not recreated or overwritten.

The regenerated HARV/BART field RDS files have local MD5 values
`f93f863df2f9d5fe4e655bbb5fb6cdcc` and `1a3844857f3fa30cfb598cc2d6cad08e`.
These are new serialized snapshots, not claims of byte identity with the lost
temporary caches. The re-downloaded HARV RGB MD5 is
`4323cb1a578d84092b563cce0264eafd`, matching the earlier recorded tile hash.

Measurements join census metadata on both plot and event. The audit preserves
the original measurement, mapping and census fields, including subplot IDs,
collection scope, protocol versions and quality flags. It selects the latest
mapping record, retaining its date and rejecting conflicting ties, following
the [NEON vegetation structure guide](https://data.neonscience.org/api/v0/documents/NEON_vegStructure_userGuide_vE.1).
This differs from the historical first-mapping/nearest-year preparation.

The declared target is live single- or multi-bole trees with DBH at least
10 cm. Mapped coordinates, known uncertainty and finite positive height are
required for the diagnostic reference subset. Multi-bole identities remain
separate. Smaller/nested populations are excluded explicitly, not treated as
exhaustively mapped; unsupported subplot encodings fail closed.

Four actual named-point corners define each sampled quadrilateral. The audit
does not expand the plot centroid into a presumed census box. Listed subplot
areas must agree with the census sampled area; missing corners, duplicates,
overlaps and invalid polygons fail. The conservative interior erodes the union
by the maximum known target/anchor uncertainty plus 0.6 m. That is a declared
boundary sensitivity rule, not a guaranteed statistical confidence interval.

## Eastern Findings

All ten census events yield measured-corner polygons for their two sampled
subplots, with nominal area 800 m2 each. Surveyed polygon areas differ from
the idealized area; they are reported rather than forced to 800 m2.

| Plot | Measured area, m2 | Interior area, m2 | Margin, m | Live DBH-qualified records | Eligible before geometry | Selected interior references |
| --- | --- | --- | --- | --- | --- | --- |
| HARV_033 | 827.23 | 727.79 | 0.85 | 41 | 35 | 30 |
| HARV_034 | 821.15 | 678.55 | 0.92 | 68 | 66 | 55 |
| HARV_038 | 818.57 | 671.54 | 0.95 | 76 | 64 | 52 |
| HARV_039 | 832.26 | 739.87 | 0.77 | 49 | 44 | 37 |
| HARV_040 | 772.18 | 684.02 | 0.77 | 40 | 35 | 30 |
| BART_036 | 785.25 | 667.69 | 0.77 | 57 | 54 | 45 |
| BART_040 | 825.07 | 700.14 | 0.80 | 42 | 39 | 36 |
| BART_042 | 854.05 | 756.89 | 0.80 | 55 | 52 | 49 |
| BART_071 | 773.60 | 686.08 | 0.75 | 52 | 50 | 41 |
| BART_073 | 813.68 | 699.96 | 0.73 | 70 | 68 | 55 |

The diagnostic interiors contain **204 HARV and 226 BART references**. These
are not the previous nominal-box population: event joining, diameter rules,
latest mapping and uncertainty boundaries differ. Do not treat their counts
as a paired change in detector recall.

| Target-record limitation before geometry | HARV | BART |
| --- | --- | --- |
| Missing mapping coordinates | 25 | 10 |
| Invalid or missing height | 5 | 2 |
| Missing mapping uncertainty | 0 | 1 |

Every plot has incomplete target references. In addition, two HARV_033 records
(`NEON.PLA.D01.HARV.05646` and `NEON.PLA.D01.HARV.05647`) lie outside their
recorded `23_400` subplot beyond their declared positional margin. Their
latest mapping date is 2023-08-14; neither is selected. The audit records the
conflict without moving a stem, selecting a convenient older mapping or
altering the sampled footprint. BART_040 has one target record with unknown
named-point uncertainty; no default uncertainty was substituted.

Manual review of `HARV_033_sampled_support.png` confirms the southern sampled
footprint and visible leaf-on canopy. White outlines show measured support,
cyan the conservative interior, white points selected references and red
points excluded mapped target records. The geometry follows surveyed corners
rather than the axis-aligned nominal box. The RGB has matching EPSG:32618 and
0.1 m cells. The overlay is not evidence of sub-metre absolute accuracy and
was not used to fit a displacement or adjust a boundary.

## Historical Audit

A read-only audit joined all archived live-tree references inside the old
nominal boxes back to their measurement events. It covers **787 references
across 86 site/plot combinations**, including plots outside particular published
comparison subsets. It is not a rescore of the common 699-stem benchmark or
the paired SOAP study.

| Census-support status | SJER | SOAP | TEAK |
| --- | --- | --- | --- |
| Partial nominal area | 33 | 127 | 204 |
| Dendrometer-only event | 3 | 17 | 27 |
| Missing sampled area | 2 | 0 | 0 |
| Unresolved census event | 42 | 11 | 19 |
| Area does not disprove nominal box; footprint still needs audit | 18 | 98 | 186 |
| Total archived core references inspected | 98 | 253 | 436 |

These are reference-record counts, not counts of affected plots or errors.
Unresolved events include missing or ambiguous individual/year joins. A
matching sampled-area total is not proof of complete geometry. Dendrometer
events must not be treated as all-tree censuses simply because their year
matches the flight. Historical precision/calibration interpretation needs a
controlled support-aware comparison, not an automatic numerical correction.

The integrity check found **5,944 protected file paths/sizes/mtimes unchanged**,
with content hashes also unchanged for **1,066 CSV/JSON/RDS files up to 20 MiB**.
Large spatial/model files were not fully content-hashed. The original dirty
worktree is unchanged. No archived cloud, prediction, calibrator or published
metric was modified.

## Scoring and Cache Boundaries

- The new polygon option in `score_plot()` preserves the existing one-to-one
  matcher and height gate. The default rectangular path and output schema are
  unchanged. Synthetic same-square comparisons reproduce its existing counts.
- `score_neon_support()` requires explicit detection CRS and an admitted
  support bundle. It filters references to the declared interior, uses the
  existing tolerance around that interior for recall and counts only interior
  detections for precision. All actual bundles fail the admission gate.
- Unmatched detections may represent real trees outside the DBH/mapped-bole
  population. Even a completed geometry audit would establish reference-relative
  detection metrics, not independently verified all-tree precision or crowns.
- Support identities bind event metadata, references, geometry, population,
  margin, code and source hashes. Preparation checks both input contracts and
  output receipts on replay. Signed cloud URLs and tokens are not archived.
- Shared pooling/equal-set checks reject missing or mixed support metadata and
  different support within the same plot, including across density rungs.
  Pooled outputs retain population/policy and a support-set identity.
- Existing model runners are not automatically migrated or authorized for
  eastern inference. This is an opt-in scoring foundation with synthetic
  comparisons, not an end-to-end detector performance benchmark.

## Reproduction and Verification

Run these commands from the implementation checkout. Generated artifacts use
a separate persistent job root:

```sh
export CLAUDE_JOB_DIR=/home/alex/projects/lidar_tree_benchmarks/work/eastern-reference-support-2022
for SITE in HARV BART; do
  Rscript scripts/neon_reference_support.R SITE="$SITE" YEAR=2022 \
    OUT="$CLAUDE_JOB_DIR/reference_support_v2/$SITE"
done
Rscript scripts/audit_neon_reference_history.R \
  SOURCE=/home/alex/projects/lidar_tree_benchmarks/work \
  OUT="$CLAUDE_JOB_DIR/reference_support_history_v2"
Rscript scripts/review_neon_reference_support.R \
  SUPPORT="$CLAUDE_JOB_DIR/reference_support_v2/HARV/support_bundles.rds" \
  OUT="$CLAUDE_JOB_DIR/reference_support_rgb_review_v2"
Rscript tests/run_tests.R
rumdl check --no-cache .
git diff --check
```

Each site exports `reference_audit.csv`, `census_events.csv`, `named_points.csv`,
`event_support_summary.csv`, `support_bundles.rds`, GeoPackage/GeoJSON footprints
and immutable input/output receipts. Raw location responses are retained.
Earlier diagnostics remain separate from the final `reference_support_v2/`
outputs. Code/protocol changes need a new output root; never replace old
manifests to make replay pass.

The full R suite passes. Focused tests cover event ambiguity, latest mappings,
target populations, missing anchors, nested rejection, different subplot pairs,
small tower layouts, boundary margins, CRS, matching, cache identities and
support-aware pooling. Standalone offline replay preserves artifact hashes;
tampered output receipts are rejected. Three existing tests skip: gated GPU
inference, an empty LAS writer fixture and optional Python `plyfile`
interoperability. An optional
R-universe index probe emits the existing network-access warning.

## Next Gate

Review the 43 incomplete target records and the two subplot conflicts under a
declared missing-reference policy. Recover trustworthy source information where
available; do not impute reference absences or choose corrections using scores.
Resolve field/AOP datum and contributing-flight provenance, then complete the
remaining physical coverage/density checks before an admission declaration.

Only after admission should a bounded comparison integrate these supports into
the declared HARV pipeline. BART remains untouched by detector evaluation.
Historical support-aware rescoring requires a separately declared comparison
and separate outputs; existing results remain historical evidence.
