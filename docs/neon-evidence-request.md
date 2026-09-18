# NEON Reference-Position and Flight Evidence Request

**Draft only: not submitted.** Prepared for the
[NEON contact form](https://www.neonscience.org/about/contact-us).
The sender must provide their own name and reply address. The questions concern
DP1.10098.001 and DP1.30003.001, RELEASE-2026, with exact-2022 field references
and August 2022 AOP at HARV/BART. No detector outputs informed these questions.

## Suggested Message

We are preparing a field-reference benchmark using event-specific sampled
subplots at HARV and BART. We have preserved the released data and would
appreciate clarification of the following positional and provenance questions.
Our [bounded evidence summary](../results/neon-positional-evidence-results.md)
records the comparisons; none has been applied as a correction.

### Azimuth Convention and HARV Subplot Margins

The 2022 field protocol, NEON.DOC.000987 revision K, describes true-north stem
azimuths. The vegetation guide/tutorial calculates offsets directly in UTM.
For event `vst_HARV_2022`, subplot `23_400`, we find:

| Individual | Mapping UID | Mapping date | Anchor | Distance, m | Azimuth, degrees |
| --- | --- | --- | --- | ---: | ---: |
| NEON.PLA.D01.HARV.05646 | 79187782-92cc-4e19-9569-0daedd7754d5 | 2023-08-14 | HARV_033.basePlot.vst.23 | 10.8 | 87.4 |
| NEON.PLA.D01.HARV.05647 | 3ee8d3e6-db1f-4068-899d-d246857c45c7 | 2023-08-14 | HARV_033.basePlot.vst.23 | 10.2 | 87.5 |

With measured subplot corners, the published UTM recipe puts the stems
0.8606/0.8306 m outside the recorded subplot, versus margins of 0.79 m.
A WGS84 true-north ellipsoidal calculation changes those distances to
0.5014/0.4913 m. We have not moved the stems or enlarged the margin.

Should released `stemAzimuth` here be treated as true north or grid north?
Is the direct UTM recipe an intentional approximation, and is its convergence
error included in the recommended uncertainty? Do the recorded subplot and
mapping values require any other interpretation? The map dates postdate the
census; we have followed the latest-map recommendation without selecting
alternative records.

### BART Anchor Uncertainty

`NEON.PLA.D01.BART.05808`, plot `BART_040`, event `vst_BART_2022`, is mapped
from `BART_040.basePlot.vst.51` by 4.4 m at 70.3 degrees (mapping date
2018-07-16). The named-point response reports source `GIS`, generic `WGS84`,
easting 316451.50147 and northing 4881740.00608 in UTM 19N, but no coordinate
uncertainty, survey epoch or realization.

Is there an authoritative uncertainty and derivation record for this point?
We have not substituted a neighboring point's uncertainty or assumed zero.

### Living Secondary with Dead Primary

In `HARV_040`, `vst_HARV_2022`, `NEON.PLA.D01.HARV.09167` is dead/broken and
`NEON.PLA.D01.HARV.09167A` is living, DBH 22.0 cm, height 14.5 m. The primary
mapping UID `334bd691-1826-4615-b510-53c9cdf98466` uses point 59 with a 5.4 m,
178.4-degree offset. The secondary's UID
`3be232d4-7962-4c9e-9241-92323da6a13a` is `tag only`, with no offsets; both
mapping rows are dated 2023-09-12.

Does the primary mapping remain a documented location for the living apparent
individual, and with what spatial interpretation/uncertainty? Is another
authoritative mapping available? We have not borrowed the dead bole's position.

### Field-Marker Datum and Epoch

The archived HARV/BART point responses use a generic WGS84 label, mostly with
coordinate source `GeoXH 6000`. The AOP datum report NEON.DOC.002293 revision B
documents its ITRF00/WGS84(G1150) convention. Where can we obtain the applicable
field-marker survey realization, epoch and absolute positional-accuracy
information, including the GIS-derived BART point? We have not assumed that
matching EPSG labels establish field-to-AOP alignment.

### HARV Point-to-Flightline Crosswalk

For classified tile
`NEON_D01_HARV_DP1_731000_4713000_classified_point_cloud_colorized.laz`, the
25 m buffer around measured HARV_033 support contains 72,866 points with Point
Source ID 7 and GPS-week time approximately 397530.4-397531.7 seconds.
August 4, 2022 is compatible with the published schedule and the archived
`2022080412_P3C1_SBET_QAQC.pdf` trajectory interval
393613.0024-405306.0009 seconds. All 40 inspected unclassified-flightline
headers in the release have File Source ID 0.

Can you provide the crosswalk from classified Point Source ID 7 to the actual
source flightline/repeat and acquisition date, or identify authoritative
metadata that establishes it? We have not equated ID 7 with filename L007-1.

## Supporting Files

The reproducible audit exports `offset_hypotheses.csv`,
`released_case_mappings.csv`, `case_measurement_history.csv`,
`named_point_evidence.csv` and `trajectory_compatibility.csv`, with source and
output hashes. The contact form currently permits up to two attachments, each
at most 10 MB, in its listed formats; a text/PDF version of this request and
summary can be used. Do not include API tokens, signed URLs or private paths.
