# NEON Positional Evidence Findings

## Decision

The 2026-09-18 bounded investigation found a plausible coordinate-convention
explanation for the two HARV_033 subplot discrepancies. It does **not** establish
an approved correction. All four individual cases remain unresolved, all
support remains diagnostic, and selection stays at **206 HARV / 226 BART**.

The [declared follow-up](../docs/neon-positional-evidence-protocol.md) uses only
archived field records, named-point metadata and trajectory reports. No new
clouds, imagery or field data were downloaded. No positions, boundaries,
reference policies, scores or admission flags were changed.

## Coordinate Convention

The [field protocol, revision K](https://data.neonscience.org/api/v0/documents/NEON.DOC.000987vK)
describes stem azimuth relative to true north. The
[published coordinate tutorial](https://www.neonscience.org/resources/learning-hub/tutorials/classification-training-data)
adds sine/cosine offsets directly to UTM easting/northing. True north and UTM
grid north need not coincide. The benchmark currently preserves that published
UTM recipe; this diagnostic compares it with an ellipsoidal true-north offset,
without choosing a replacement from the outcome.

| HARV_033 individual suffix | Recorded distance, m | Azimuth, degrees | Position difference, m | Existing recipe: subplot distance, m | True-north hypothesis: subplot distance, m | Existing margin, m |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 05646 | 10.8 | 87.4 | 0.3601 | 0.8606 | 0.5014 | 0.79 |
| 05647 | 10.2 | 87.5 | 0.3401 | 0.8306 | 0.4913 | 0.79 |

Both hypotheses use `HARV_033.basePlot.vst.23` and the same measured `23_400`
subplot polygon. The alternative uses `sf`/PROJ's WGS84 azimuthal-equidistant
implementation centered on the anchor transformed from unrounded UTM values,
not the API's rounded geographic coordinates. Existing positions are reproduced
within 0.0000001 m before comparison.

Both alternative positions fall within the unchanged margin. This is evidence
that the convention matters, **not proof of a field error or permission to
move the trees**. Ask NEON which interpretation applies to these released
measurements, whether the guide's approximation is intentional, and how its
error relates to the uncertainty budget. A correction would need a separately
declared comparison across affected references, not just these two cases.

## Released Position Evidence

The source table contains one released mapping row for each of the five
inspected bole IDs. It is not a complete history of mapping revisions.

| Plot and individual suffix | Mapping date | Record type | Anchor | Offset |
| --- | --- | --- | --- | --- |
| HARV_033 05646 | 2023-08-14 | map and tag | 23 | 10.8 m, 87.4 degrees |
| HARV_033 05647 | 2023-08-14 | map and tag | 23 | 10.2 m, 87.5 degrees |
| HARV_040 09167 | 2023-09-12 | map and tag | 59 | 5.4 m, 178.4 degrees |
| HARV_040 09167A | 2023-09-12 | tag only | None | None |
| BART_040 05808 | 2018-07-16 | map and tag | 51 | 4.4 m, 70.3 degrees |

The 45 retained measurement-history rows provide context, not replacement
measurements. HARV 09167 is already standing dead in 2017; 09167A is living in
the target 2022 event. There is no independently mapped location for 09167A in
the released mapping table. The older primary's position was not borrowed.

Across 67 archived named-point responses, 66 list `GeoXH 6000` as coordinate
source; `BART_040.basePlot.vst.51` alone lists `GIS` and lacks uncertainty.
All 67 use the generic WGS84 label and have no explicit survey-epoch or datum-
realization property. Receiver labels are not realizations or survey dates.
These findings concern the archived responses, not all possible NEON records.

## Trajectory Compatibility

The archived HARV_033 point-time range, about 397530.4-397531.7 GPS-week
seconds, fits the August 4 trajectory interval and the existing schedule
candidate. The other three archived mission intervals do not contain it.

| Mission date | Trajectory start, GPS-week seconds | Trajectory end, GPS-week seconds | Point-time and schedule compatible |
| --- | ---: | ---: | --- |
| 2022-08-03 | 306863.0012 | 316340.0048 | No |
| 2022-08-04 | 393613.0024 | 405306.0009 | Yes |
| 2022-08-12 | 481086.0015 | 490864.0038 | No |
| 2022-08-14 | 49350.0023 | 57537.0004 | No |

This corroborates the mission-time candidate, not the exact source flightline.
All 40 previously inspected source headers still have File Source ID zero.
The classified tile's Point Source ID 7 cannot be equated with filename L007-1
without the missing crosswalk. No flightline clouds were downloaded or read.

## Next Action

The [NEON evidence request](../docs/neon-evidence-request.md) is a prepared,
**unsent** draft containing the identifiers, comparisons and precise questions.
The public contact form is a submission route, not evidence that a ticket
exists. No external inquiry was submitted during this work.

The bounded investigation stops here pending authoritative clarification of
the offset convention, BART uncertainty, mixed live/dead family location,
field-marker datum/epoch and flightline identity. Do not repeat these downloads
or relax the policy just to clear the gate. Synthetic detection-pipeline
contracts can progress independently; physical coverage/density checks and
explicit admission still precede real eastern evaluation.

## Reproduction and Verification

```sh
export CLAUDE_JOB_DIR=/home/alex/projects/lidar_tree_benchmarks/work/eastern-reference-support-2022
Rscript scripts/audit_neon_positional_evidence.R \
  SOURCE="$CLAUDE_JOB_DIR" OUT="$CLAUDE_JOB_DIR/positional_evidence_v1"
Rscript tests/run_tests.R
rumdl check --no-cache .
git diff --check
```

The script requires the archived snapshot layout described in the protocol,
the existing `sf`/PROJ installation and `pdftotext`. It installs nothing and
makes no network requests. CSVs retain source IDs, measurement histories,
mapping rows, anchor metadata, both offset hypotheses and trajectory intervals.
The extracted PDF text and immutable receipts stay in the working directory.

All **220 protected input/code/protocol hashes** remain unchanged. The actual
run and offline replay pass. All 39 focused assertions and the full R suite
pass, with three existing skips and the optional R-universe package-index
warning. Original field data, references, geometries and the dirty checkout
remain unchanged.
