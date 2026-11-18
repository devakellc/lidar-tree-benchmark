# Open Forest Observatory stem maps: second preflight results

Checked on 17 November 2026. The [first preflight](ofo-preflight-results.md)
ended no-go for every plot group. This second preflight follows the
[second protocol](../docs/ofo-preflight-protocol-2.md), declared before any of
the evidence below was computed. It covers groups A and B only, tests the
unchanged registration method against a truth that does not rest on NEON
stem positions, and replaces the drone check with disturbance sources that
cover the years between survey and flight. It is score-blind: no detector
was run on these plots and nothing was scored.

**Decision: hold for groups A and B, on this preflight's reading of the
protocol; read strictly, no-go.** The crown-frame test of the registration
could not be completed. Five units per signal had a credible truth, and the
pass rule needs ten. No signal is admitted, no plot is registered, and no
reference table was written. Either way nothing further is authorised. The
reading is set out under Decision.

**Status: closed on 18 November 2026, with this decision standing.** Neither
way of ending the hold was taken up. The stem maps of the catalogue are not
part of the benchmark's reference, and no detector has been run on them.

What the evidence shows, short of a completed test:

- **Where the truth is credible, the method agrees with it.** All five
  units of each signal lie within 2 m of crowns drawn by people, with a
  median error of 0.39 m for heights and 0.38 m for diameters. On four of
  the five the crown truth lies about 1 m or less from NEON's mapped stems,
  so the first protocol's truth gives much the same result there;
  `ABBY_063` is where the two truths part.
- **The truth, not the method, ran short.** The declared way of placing
  stems on crown boxes gave a credible answer on 5 of 31 annotated plots.
- **One first-protocol failure is explained.** At `ABBY_063` the drawn
  crowns, carried into the frame of the method's surface, lie 2.97 m north
  of NEON's mapped stems, and the method's estimate is 0.39 m from them.
  Its 2.61 m "error" in the first protocol was a real offset between that
  stem map and its canopy. `ABBY_063` belongs to the benchmark's headline
  NEON population, which is matched at 4 m; how a 3 m offset of its stem
  map affects the NEON results at Abby Road was not examined.
- **Twelve catalogue plots fail only on unmade checks**: 3 in group A and 9
  in group B. Three more have Forest Service harvest or burning records
  inside their interval. Four fail the guard against a competing alignment:
  the three `JLHZ2019` plots and `MNPK2018` plot 0200, which is also on the
  edge of the search window.

## Decision

| Group | Decision | Signal | Signal admitted | Plots admitted | Plots with headline cells | Reference stems in headline cells | Group floor, cm | Reasons |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A | hold | height | no | 0 | 0 | 0 | 10.0 | signal height not admitted: its test was inconclusive (read as a check that could not be made); 0 admitted plots (need 3), 0 with a headline cell; 0 reference stems in their headline cells (need 100); no admitted plot whose licence to check; with 3 plots failing only unchecked checks: 3 plots, 1965 stems |
| B | hold | rank | no | 0 | 0 | 0 | 10.0 | signal rank not admitted: its test was inconclusive (read as a check that could not be made); 0 admitted plots (need 3), 0 with a headline cell; 0 reference stems in their headline cells (need 100); no admitted plot whose licence to check; with 9 plots failing only unchecked checks: 9 plots, 1449 stems |

The test of each signal was inconclusive, so its group cannot be go. The
second protocol does not say how an inconclusive test enters the group
rule. It names a test with fewer than ten units inconclusive, apart from a
test that fails, and makes only a failed test no-go. This preflight
therefore counts an inconclusive test as a check that could not be made,
and the protocol holds a group that fails only on such checks. That is a
reading made after the test, not a declared rule. Read by the first
protocol instead, where a group whose signal is not admitted is no-go, both
groups would be no-go.

To evaluate the hold rule, plots whose registration is only unchecked were
placed provisionally at the method's estimate. The protocol does not
describe that step, and no plot is admitted on it. Counting the plots whose
every failure is an unmade check, group A would have 3 plots with 1,965
reference stems in headline cells and group B 9 plots with 1,449, both
above the three plots and 100 stems the rule asks. Like no-go, hold
authorises nothing further.

The hold could end in two ways, and both need a decision outside this
protocol, which allows no redesign:

- a crown-frame truth that is credible on enough plots, by another way of
  placing stems on crowns or by more annotated plots; or
- accepting the method on the evidence here, as an exploratory reference
  that is labelled as such.

Neither was taken up. The study was closed on 18 November 2026 and left as
it stands: no plot of the catalogue is registered, no clip is frozen and no
detector is run on these plots. Taking the data up again needs a new
decision and a new protocol.

## What was run

| Stage | Script | Writes under `<job>/ofo/preflight2` |
| --- | --- | --- |
| Crown annotations, truth and the test | [preflight_ofo_crowntruth.R](../scripts/preflight_ofo_crowntruth.R) | `nte/`, crown truth, test units, test record |
| NIWO stems, clips and registration | [preflight_ofo_niwo.R](../scripts/preflight_ofo_niwo.R) | `niwo/`, NIWO units and estimates |
| Fire and activity records, canopy check | [preflight_ofo_disturbance.R](../scripts/preflight_ofo_disturbance.R) | `records/`, disturbance table |
| Gates, conditions and the decision | [preflight_ofo2_assemble.R](../scripts/preflight_ofo2_assemble.R), [preflight_ofo_decision.R](../scripts/preflight_ofo_decision.R) | Registration, conditions, cells, admission, decision |
| Tables of this report | [report_ofo_preflight2.R](../scripts/report_ofo_preflight2.R) | `report_tables.md` |

Every table below is copied from the output of the last script. The first
protocol's outputs were read and not rewritten; its decision stage, rerun
with the code as it now stands, reproduces them byte for byte.

## Crown-frame truth

The truth for a NEON plot is the shift that moves its mapped stems onto the
crown boxes of the NeonTreeEvaluation benchmark, tied to the frame of the
method's canopy surface. Nineteen annotated plots of the five benchmark
sites and twelve of NIWO were eligible. The annotations were taken at one
commit of the public repository, 210 files in all.

| Plot | Site | Source | Year | Boxes | Truth stems | Truth dx, dy (image), m | On edge | s90, m | Tie dx, dy, m | Tie NCC | Tie on edge | Truth dx, dy (method frame), m | Mapped stems to crowns (method frame), m | Credible | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ABBY_063 | ABBY | benchmark | 2019 | 57 | 22 | <0.01, 2.95 | no | 0.36 | 0.02, 0.02 | 0.91 | no | 0.02, 2.97 | 2.97 | yes | — |
| ABBY_076 | ABBY | benchmark | 2019 | 103 | 29 | 0.76, -0.68 | no | 0.27 | -0.02, 0.01 | 0.87 | no | 0.74, -0.68 | 1.00 | yes | — |
| SJER_046 | SJER | benchmark | 2018 | 14 | 6 | -2.58, -0.80 | no | 1.47 | -0.02, 0.02 | 0.85 | no | -2.60, -0.78 | 2.71 | no | n;s90 |
| SJER_050 | SJER | benchmark | 2018 | 15 | 7 | 0.32, -0.59 | no | 11.31 | -0.02, -0.08 | 0.94 | no | 0.30, -0.66 | 0.73 | no | n;s90 |
| SJER_051 | SJER | benchmark | 2018 | 13 | 1 | 11.72, -9.77 | no | 0.00 | -0.09, 0.02 | 0.91 | no | 11.63, -9.75 | 15.18 | no | n |
| SJER_052 | SJER | benchmark | 2018 | 9 | 1 | 11.42, 12.00 | yes | 0.00 | -0.46, -0.01 | 0.92 | no | 10.96, 11.99 | 16.25 | no | n;on_edge |
| SJER_053 | SJER | benchmark | 2018 | 11 | 6 | 0.06, 0.42 | no | 10.99 | -0.44, 0.04 | 0.93 | no | -0.38, 0.47 | 0.60 | no | n;s90 |
| SOAP_031 | SOAP | benchmark | 2019 | 59 | 25 | 0.21, 2.50 | no | 13.24 | 0.01, 0.01 | 0.63 | no | 0.22, 2.50 | 2.51 | no | s90 |
| TEAK_043 | TEAK | benchmark | 2018 | 24 | 8 | -0.82, 0.58 | no | 3.16 | 0.07, 0.04 | 0.87 | no | -0.75, 0.62 | 0.97 | no | s90 |
| TEAK_044 | TEAK | benchmark | 2018 | 36 | 38 | 0.39, 0.55 | no | 6.92 | -0.07, -0.03 | 0.91 | no | 0.32, 0.53 | 0.62 | no | s90 |
| TEAK_045 | TEAK | benchmark | 2018 | 39 | 21 | 6.73, -0.18 | no | 13.28 | -0.43, -0.07 | 0.94 | no | 6.30, -0.25 | 6.30 | no | s90 |
| TEAK_046 | TEAK | benchmark | 2018 | 39 | 32 | 1.77, -7.11 | no | 8.18 | -0.48, -0.49 | 0.87 | no | 1.29, -7.59 | 7.70 | no | s90 |
| TEAK_047 | TEAK | benchmark | 2018 | 36 | 27 | -1.69, 0.41 | no | 10.91 | -0.49, -0.23 | 0.82 | no | -2.18, 0.18 | 2.19 | no | s90 |
| TEAK_052 | TEAK | benchmark | 2018 | 73 | 10 | -6.11, -7.70 | no | 15.24 | -0.49, 0.09 | 0.87 | no | -6.59, -7.61 | 10.07 | no | s90 |
| WREF_070 | WREF | benchmark | 2019 | 55 | 13 | 9.93, -3.55 | no | 15.50 | 0.05, -0.03 | 0.97 | no | 9.98, -3.57 | 10.60 | no | s90 |
| WREF_072 | WREF | benchmark | 2019 | 20 | 2 | 7.95, 4.00 | no | 14.11 | <0.01, 0.01 | 0.95 | no | 7.95, 4.01 | 8.90 | no | n;s90 |
| WREF_075 | WREF | benchmark | 2019 | 49 | 44 | 2.28, -1.01 | no | 12.78 | 0.01, -0.05 | 0.89 | no | 2.28, -1.05 | 2.51 | no | s90 |
| WREF_083 | WREF | benchmark | 2019 | 25 | 10 | 0.63, -3.40 | no | 15.28 | <0.01, 0.01 | 0.88 | no | 0.63, -3.39 | 3.45 | no | s90 |
| WREF_084 | WREF | benchmark | 2019 | 29 | 17 | -0.61, -0.65 | no | 5.81 | -0.03, -0.03 | 0.94 | no | -0.64, -0.68 | 0.93 | no | s90 |
| NIWO_001 | NIWO | niwo | 2018 | 176 | 41 | -0.03, -0.91 | no | 0.30 | 0.03, <0.01 | 0.85 | no | >-0.01, -0.91 | 0.91 | yes | — |
| NIWO_002 | NIWO | niwo | 2018 | 292 | 68 | 0.41, -0.60 | no | 9.18 | 0.04, -0.45 | 0.71 | no | 0.45, -1.05 | 1.14 | no | s90 |
| NIWO_004 | NIWO | niwo | 2018 | 107 | 44 | 0.64, -0.06 | no | 0.69 | 0.01, 0.01 | 0.85 | no | 0.65, -0.05 | 0.65 | yes | — |
| NIWO_005 | NIWO | niwo | 2018 | 146 | 36 | 0.03, -0.73 | no | 0.47 | 0.01, >-0.01 | 0.84 | no | 0.04, -0.73 | 0.73 | yes | — |
| NIWO_010 | NIWO | niwo | 2018 | 148 | 51 | 0.30, -0.47 | no | 7.02 | -0.01, 0.02 | 0.82 | no | 0.30, -0.45 | 0.54 | no | s90 |
| NIWO_011 | NIWO | niwo | 2018 | 153 | 45 | -0.07, -0.59 | no | 5.15 | — | — | — | — | — | no | no_chm;s90;tie_ncc;tie_on_edge |
| NIWO_012 | NIWO | niwo | 2018 | 136 | 36 | 1.40, -0.03 | no | 14.40 | 0.05, -0.01 | 0.83 | no | 1.45, -0.04 | 1.46 | no | s90 |
| NIWO_014 | NIWO | niwo | 2018 | 179 | 40 | -0.41, -0.43 | no | 11.37 | 0.06, <0.01 | 0.80 | no | -0.35, -0.43 | 0.55 | no | s90 |
| NIWO_015 | NIWO | niwo | 2018 | 150 | 58 | -0.50, -0.24 | no | 1.38 | 0.02, -0.01 | 0.90 | no | -0.48, -0.25 | 0.54 | no | s90 |
| NIWO_016 | NIWO | niwo | 2018 | 134 | 29 | -3.13, 7.31 | no | 21.17 | 0.06, -0.03 | 0.77 | no | -3.07, 7.28 | 7.90 | no | s90 |
| NIWO_017 | NIWO | niwo | 2018 | 151 | 41 | 0.06, -0.77 | no | 13.12 | -0.04, -0.02 | 0.74 | no | 0.02, -0.79 | 0.79 | no | s90 |
| NIWO_042 | NIWO | niwo | 2018 | 5 | 0 | — | — | — | 0.39, 0.10 | 0.82 | no | — | — | no | n;on_edge;s90 |

Five truths are credible. Of the other 26, 23 fail the stability rule: the
90th percentile of the bootstrap distances exceeds 1 m, usually by far.
`NIWO_042` has no truth stem to resample and fails it too. On the unstable
plots, resampling the stems moves the answer between shifts that score
alike. The likely reasons differ by site. On the benchmark plots, with
few and large boxes, many stems lie far from any box centre: at the truth,
the median distance to the nearest centre exceeds 1.5 m on 7 of the 19
plots. At NIWO the stems lie close to box centres, at medians of 0.6 to
1.1 m, but the boxes are small and dense, more than 100 per image, so other
shifts also put most stems near some box.

Seven plots have fewer than 8 truth stems; for `SJER_051` and `SJER_052`,
with one stem each, that is the only failure besides the window's edge at
`SJER_052`. `NIWO_011` has no canopy height model for its annotation year.
Where the
frame tie could be computed it is sound: its correlation is between 0.63
and 0.97 and never on the edge.

A truth that is not credible is no evidence either way. `SOAP_031` and
`TEAK_046`, which failed the first protocol under both signals, are among
them, so this test says nothing about those two plots.

## The test

The benchmark units reuse the frozen method's estimates from the first
protocol, unchanged. The NIWO units were run once, on clips built with the
benchmark's own provider from the site's 2020 flight. The code path that
ran them reproduces the first protocol's rows for three benchmark plots
exactly. Ten of the twelve NIWO plots were accepted by the frozen gate under
each signal.

| Source | Half | Plot | Variant | Stems | At smallest count | Accepted | Estimate dx, dy, m | Truth dx, dy, m | Credible | Crown error, m | Zero error, m | In test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| benchmark | confirmation | ABBY_063 | ncc | 38 | yes | yes | -0.12, 2.61 | 0.02, 2.97 | yes | 0.39 | 2.61 | yes |
| benchmark | development | ABBY_076 | ncc | 41 | yes | yes | 0.79, -0.83 | 0.74, -0.68 | yes | 0.16 | 1.14 | yes |
| niwo | niwo | NIWO_001 | ncc | 43 | yes | yes | 0.24, -0.54 | >-0.01, -0.91 | yes | 0.44 | 0.59 | yes |
| niwo | niwo | NIWO_004 | ncc | 45 | yes | yes | 0.14, -0.16 | 0.65, -0.05 | yes | 0.52 | 0.21 | yes |
| niwo | niwo | NIWO_005 | ncc | 36 | yes | yes | 0.29, -0.66 | 0.04, -0.73 | yes | 0.26 | 0.72 | yes |
| benchmark | confirmation | SJER_046 | ncc | 6 | no | no | -5.80, 2.10 | -2.60, -0.78 | no | 4.31 | 6.17 | no |
| benchmark | confirmation | SJER_051 | ncc | 2 | no | no | — | 11.63, -9.75 | no | — | — | no |
| benchmark | confirmation | SJER_052 | ncc | 2 | no | no | — | 10.96, 11.99 | no | — | — | no |
| benchmark | confirmation | SOAP_031 | ncc | 35 | yes | yes | 0.61, -2.67 | 0.22, 2.50 | no | 5.19 | 2.74 | no |
| benchmark | confirmation | TEAK_045 | ncc | 31 | yes | no | 1.90, 2.07 | 6.30, -0.25 | no | 4.98 | 2.81 | no |
| benchmark | confirmation | TEAK_046 | ncc | 51 | yes | yes | 1.53, -2.05 | 1.29, -7.59 | no | 5.55 | 2.56 | no |
| benchmark | confirmation | TEAK_047 | ncc | 34 | yes | yes | 0.38, 0.02 | -2.18, 0.18 | no | 2.57 | 0.38 | no |
| benchmark | confirmation | WREF_070 | ncc | 40 | yes | no | 0.41, -0.37 | 9.98, -3.57 | no | 10.09 | 0.55 | no |
| benchmark | confirmation | WREF_084 | ncc | 18 | no | no | -0.21, 0.02 | -0.64, -0.68 | no | 0.82 | 0.22 | no |
| benchmark | development | SJER_050 | ncc | 9 | no | no | -0.64, 1.16 | 0.30, -0.66 | no | 2.05 | 1.32 | no |
| benchmark | development | SJER_053 | ncc | 8 | no | no | -0.01, -0.52 | -0.38, 0.47 | no | 1.05 | 0.52 | no |
| benchmark | development | TEAK_043 | ncc | 24 | yes | yes | -0.16, 0.59 | -0.75, 0.62 | no | 0.59 | 0.62 | no |
| benchmark | development | TEAK_044 | ncc | 81 | yes | yes | 0.04, 0.71 | 0.32, 0.53 | no | 0.34 | 0.71 | no |
| benchmark | development | TEAK_052 | ncc | 10 | no | no | -11.41, -2.71 | -6.59, -7.61 | no | 6.87 | 11.73 | no |
| benchmark | development | WREF_072 | ncc | 11 | no | no | 12.81, -15.34 | 7.95, 4.01 | no | 19.95 | 19.98 | no |
| benchmark | development | WREF_075 | ncc | 70 | yes | yes | 0.21, -0.79 | 2.28, -1.05 | no | 2.09 | 0.81 | no |
| benchmark | development | WREF_083 | ncc | 17 | no | no | 0.04, -3.57 | 0.63, -3.39 | no | 0.62 | 3.57 | no |
| niwo | niwo | NIWO_002 | ncc | 76 | yes | yes | 0.22, -0.58 | 0.45, -1.05 | no | 0.52 | 0.62 | no |
| niwo | niwo | NIWO_010 | ncc | 68 | yes | yes | 0.19, 0.09 | 0.30, -0.45 | no | 0.55 | 0.21 | no |
| niwo | niwo | NIWO_011 | ncc | 52 | yes | yes | -0.39, -0.15 | — | no | — | 0.42 | no |
| niwo | niwo | NIWO_012 | ncc | 44 | yes | no | 0.87, -0.43 | 1.45, -0.04 | no | 0.70 | 0.97 | no |
| niwo | niwo | NIWO_014 | ncc | 47 | yes | yes | 0.60, -0.43 | -0.35, -0.43 | no | 0.95 | 0.73 | no |
| niwo | niwo | NIWO_015 | ncc | 65 | yes | yes | -0.17, 0.02 | -0.48, -0.25 | no | 0.42 | 0.17 | no |
| niwo | niwo | NIWO_016 | ncc | 34 | yes | yes | 0.27, -0.92 | -3.07, 7.28 | no | 8.85 | 0.96 | no |
| niwo | niwo | NIWO_017 | ncc | 44 | yes | yes | 0.28, -0.68 | 0.02, -0.79 | no | 0.27 | 0.73 | no |
| niwo | niwo | NIWO_042 | ncc | 2 | no | no | — | — | no | — | — | no |

| Source | Half | Plot | Variant | Stems | At smallest count | Accepted | Estimate dx, dy, m | Truth dx, dy, m | Credible | Crown error, m | Zero error, m | In test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| benchmark | confirmation | ABBY_063 | ncc_r2 | 32 | yes | yes | -0.10, 2.61 | 0.02, 2.97 | yes | 0.38 | 2.61 | yes |
| benchmark | development | ABBY_076 | ncc_r2 | 36 | yes | yes | 0.81, -0.82 | 0.74, -0.68 | yes | 0.16 | 1.15 | yes |
| niwo | niwo | NIWO_001 | ncc_r2 | 43 | yes | yes | 0.28, -0.50 | >-0.01, -0.91 | yes | 0.50 | 0.58 | yes |
| niwo | niwo | NIWO_004 | ncc_r2 | 44 | yes | yes | 0.20, -0.05 | 0.65, -0.05 | yes | 0.45 | 0.21 | yes |
| niwo | niwo | NIWO_005 | ncc_r2 | 37 | yes | yes | 0.34, -0.71 | 0.04, -0.73 | yes | 0.30 | 0.79 | yes |
| benchmark | confirmation | SJER_046 | ncc_r2 | 6 | no | no | -5.80, 2.14 | -2.60, -0.78 | no | 4.33 | 6.18 | no |
| benchmark | confirmation | SJER_051 | ncc_r2 | 14 | yes | yes | 11.92, 5.69 | 11.63, -9.75 | no | 15.45 | 13.21 | no |
| benchmark | confirmation | SJER_052 | ncc_r2 | 8 | no | no | -19.48, -6.11 | 10.96, 11.99 | no | 35.42 | 20.42 | no |
| benchmark | confirmation | SOAP_031 | ncc_r2 | 35 | yes | yes | 0.63, -2.28 | 0.22, 2.50 | no | 4.80 | 2.37 | no |
| benchmark | confirmation | TEAK_045 | ncc_r2 | 31 | yes | no | -3.23, 5.84 | 6.30, -0.25 | no | 11.31 | 6.68 | no |
| benchmark | confirmation | TEAK_046 | ncc_r2 | 51 | yes | yes | 1.22, -1.86 | 1.29, -7.59 | no | 5.74 | 2.22 | no |
| benchmark | confirmation | TEAK_047 | ncc_r2 | 32 | yes | yes | -0.04, 0.66 | -2.18, 0.18 | no | 2.20 | 0.66 | no |
| benchmark | confirmation | WREF_070 | ncc_r2 | 40 | yes | yes | 0.58, 0.28 | 9.98, -3.57 | no | 10.17 | 0.64 | no |
| benchmark | confirmation | WREF_084 | ncc_r2 | 18 | yes | no | -0.14, -0.17 | -0.64, -0.68 | no | 0.71 | 0.23 | no |
| benchmark | development | SJER_050 | ncc_r2 | 22 | yes | no | -3.81, 0.31 | 0.30, -0.66 | no | 4.23 | 3.83 | no |
| benchmark | development | SJER_053 | ncc_r2 | 10 | yes | no | -0.19, -0.48 | -0.38, 0.47 | no | 0.96 | 0.51 | no |
| benchmark | development | TEAK_043 | ncc_r2 | 17 | yes | yes | -0.43, 0.42 | -0.75, 0.62 | no | 0.38 | 0.60 | no |
| benchmark | development | TEAK_044 | ncc_r2 | 78 | yes | yes | -0.21, 0.79 | 0.32, 0.53 | no | 0.60 | 0.82 | no |
| benchmark | development | TEAK_052 | ncc_r2 | 12 | yes | no | -11.46, -1.72 | -6.59, -7.61 | no | 7.64 | 11.59 | no |
| benchmark | development | WREF_072 | ncc_r2 | 14 | yes | no | 0.57, 3.43 | 7.95, 4.01 | no | 7.40 | 3.48 | no |
| benchmark | development | WREF_075 | ncc_r2 | 68 | yes | yes | 0.50, -0.83 | 2.28, -1.05 | no | 1.80 | 0.96 | no |
| benchmark | development | WREF_083 | ncc_r2 | 17 | yes | no | 0.16, -3.70 | 0.63, -3.39 | no | 0.56 | 3.70 | no |
| niwo | niwo | NIWO_002 | ncc_r2 | 72 | yes | yes | 0.20, -0.58 | 0.45, -1.05 | no | 0.53 | 0.62 | no |
| niwo | niwo | NIWO_010 | ncc_r2 | 64 | yes | yes | 0.23, 0.09 | 0.30, -0.45 | no | 0.54 | 0.24 | no |
| niwo | niwo | NIWO_011 | ncc_r2 | 46 | yes | yes | -0.48, -0.17 | — | no | — | 0.51 | no |
| niwo | niwo | NIWO_012 | ncc_r2 | 43 | yes | no | -1.91, 0.74 | 1.45, -0.04 | no | 3.45 | 2.05 | no |
| niwo | niwo | NIWO_014 | ncc_r2 | 45 | yes | yes | 0.71, -0.57 | -0.35, -0.43 | no | 1.07 | 0.91 | no |
| niwo | niwo | NIWO_015 | ncc_r2 | 63 | yes | yes | -0.19, -0.08 | -0.48, -0.25 | no | 0.34 | 0.20 | no |
| niwo | niwo | NIWO_016 | ncc_r2 | 34 | yes | yes | 0.24, -0.94 | -3.07, 7.28 | no | 8.86 | 0.97 | no |
| niwo | niwo | NIWO_017 | ncc_r2 | 42 | yes | yes | 0.46, -0.64 | 0.02, -0.79 | no | 0.46 | 0.79 | no |
| niwo | niwo | NIWO_042 | ncc_r2 | 0 | no | no | — | — | no | — | — | no |

| Statistic | height (`signals.height`) | rank (`signals.rank`) |
| --- | --- | --- |
| variant | ncc | ncc_r2 |
| min_stems | 20 | 10 |
| units | 5 | 5 |
| median_error_m | 0.388132 | 0.381082 |
| n_within_2m | 5 | 5 |
| share_within_2m | 1 | 1 |
| pass | false | false |
| inconclusive | true | true |
| admitted | false | false |
| subsets.benchmark_development.units | 1 | 1 |
| subsets.benchmark_development.median_error_m | 0.159714 | 0.160718 |
| subsets.benchmark_development.n_within_2m | 1 | 1 |
| subsets.benchmark_development.share_within_2m | 1 | 1 |
| subsets.benchmark_development.pass | false | false |
| subsets.benchmark_development.inconclusive | true | true |
| subsets.benchmark_confirmation.units | 1 | 1 |
| subsets.benchmark_confirmation.median_error_m | 0.388132 | 0.381082 |
| subsets.benchmark_confirmation.n_within_2m | 1 | 1 |
| subsets.benchmark_confirmation.share_within_2m | 1 | 1 |
| subsets.benchmark_confirmation.pass | false | false |
| subsets.benchmark_confirmation.inconclusive | true | true |
| subsets.benchmark.units | 2 | 2 |
| subsets.benchmark.median_error_m | 0.273923 | 0.2709 |
| subsets.benchmark.n_within_2m | 2 | 2 |
| subsets.benchmark.share_within_2m | 1 | 1 |
| subsets.benchmark.pass | false | false |
| subsets.benchmark.inconclusive | true | true |
| subsets.niwo.units | 3 | 3 |
| subsets.niwo.median_error_m | 0.438003 | 0.450719 |
| subsets.niwo.n_within_2m | 3 | 3 |
| subsets.niwo.share_within_2m | 1 | 1 |
| subsets.niwo.pass | false | false |
| subsets.niwo.inconclusive | true | true |
| error_zero_same_units.units | 5 | 5 |
| error_zero_same_units.median_error_m | 0.723394 | 0.786824 |
| error_zero_same_units.n_within_2m | 4 | 4 |
| error_zero_same_units.share_within_2m | 0.8 | 0.8 |
| error_zero_same_units.pass | false | false |
| error_zero_same_units.inconclusive | true | true |
| units_by_outcome.in_test | 5 | 5 |
| units_by_outcome.truth_not_credible | 13 | 15 |
| units_by_outcome.not_accepted | 3 | 8 |
| units_by_outcome.below_min_stems | 7 | 2 |
| units_by_outcome.not_run | 3 | 1 |

Each signal has five units in the test: two benchmark plots and three NIWO
plots. All five are within 2 m, with a median error of 0.39 m for heights
and 0.38 m for diameters. Ten are needed, so the test is inconclusive and
no signal is admitted.

Two readings are reported, not tested:

- **NIWO against its mapped positions.** All ten accepted NIWO units of
  each signal lie within 1 m of NEON's mapped stem positions, with a median
  of 0.6 m. This is the first protocol's kind of truth at a site the method
  had never seen.
- **Units whose truth is unstable.** On the accepted benchmark units whose
  truth fails the stability rule, the method lies a median of 2.3 m
  (heights) and 2.2 m (diameters) from that truth and 0.8 m from the mapped
  positions. An unstable truth does not agree with the method, as would be
  expected of a truth that moves when its stems are resampled. `SJER_051`,
  accepted under the diameter signal, has a single truth stem and lies
  15.4 m from it.

## Registering catalogue plots

No plot is registered, because no signal is admitted. The frozen gate and
the two new checks were still applied to every candidate.

| Group | Signal | Signal admitted | Candidates | Flight admitted | Accepted by the frozen gate | One clear peak | Signals agree | Registered |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A | height | no | 13 | 6 | 6 | 3 | 3 | 0 |
| B | rank | no | 32 | 13 | 12 | 12 | 12 | 0 |

| Plot | Project | Group | Signal | Stems | dx, dy, m | Frozen gate | second_peak | One clear peak | Diameter accepted (A) | Height to diameter, m | Signals agree | Registered | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0068 | EP2018 | A | height | 1,841 | 1.77, -1.06 | yes | 0.656 | yes | yes | 0.12 | yes | no | signal_not_admitted |
| 0084 | JLHZ2019 | A | height | 725 | -0.75, -0.71 | yes | 0.831 | no | yes | 1.42 | yes | no | signal_not_admitted;second_peak |
| 0085 | JLHZ2019 | A | height | 1,375 | 0.40, -2.19 | yes | 0.816 | no | no | 0.79 | yes | no | signal_not_admitted;second_peak |
| 0086 | JLHZ2019 | A | height | 1,577 | 1.59, -0.05 | yes | 0.820 | no | no | 2.20 | yes | no | signal_not_admitted;second_peak |
| 0282 | SSMT2024 | A | height | 936 | 2.48, -0.17 | yes | 0.606 | yes | yes | 0.01 | yes | no | signal_not_admitted |
| 0283 | SSMT2024 | A | height | 935 | 0.77, -2.36 | yes | 0.735 | yes | yes | 0.03 | yes | no | signal_not_admitted |
| 0073 | STEF2018 | B | rank | 309 | <0.01, 0.13 | yes | 0.611 | yes | — | — | yes | no | signal_not_admitted |
| 0074 | STEF2018 | B | rank | 416 | -0.06, -0.12 | yes | 0.604 | yes | — | — | yes | no | signal_not_admitted |
| 0075 | STEF2018 | B | rank | 499 | -0.13, 0.02 | yes | 0.471 | yes | — | — | yes | no | signal_not_admitted |
| 0076 | STEF2018 | B | rank | 338 | -0.08, 0.14 | yes | 0.443 | yes | — | — | yes | no | signal_not_admitted |
| 0077 | STEF2018 | B | rank | 319 | -0.10, -0.08 | yes | 0.457 | yes | — | — | yes | no | signal_not_admitted |
| 0078 | STEF2018 | B | rank | 302 | -0.13, -0.03 | yes | 0.571 | yes | — | — | yes | no | signal_not_admitted |
| 0080 | STEF2018 | B | rank | 377 | -0.02, 0.08 | yes | 0.568 | yes | — | — | yes | no | signal_not_admitted |
| 0197 | MNPK2018 | B | rank | 109 | -1.00, -5.08 | yes | 0.599 | yes | — | — | yes | no | signal_not_admitted |
| 0198 | MNPK2018 | B | rank | 117 | 1.39, -1.19 | yes | 0.769 | yes | — | — | yes | no | signal_not_admitted |
| 0199 | MNPK2018 | B | rank | 129 | 6.11, 2.77 | yes | 0.546 | yes | — | — | yes | no | signal_not_admitted |
| 0200 | MNPK2018 | B | rank | 59 | -12.00, -5.06 | no | 0.812 | no | — | — | yes | no | signal_not_admitted;on_edge;second_peak |
| 0201 | MNPK2018 | B | rank | 138 | -5.86, -0.77 | yes | 0.622 | yes | — | — | yes | no | signal_not_admitted |
| 0202 | MNPK2018 | B | rank | 100 | 0.69, -1.81 | yes | 0.648 | yes | — | — | yes | no | signal_not_admitted |

- **One clear peak.** The three `JLHZ2019` plots fail it, with a second
  alignment at 0.82 to 0.83 of the best against a limit of 0.8. The two
  planted `SSMT2024` plots, which the check was written for, pass at 0.606
  and 0.735.
- **Signals agree.** Wherever the diameter signal is also accepted in group
  A, the two estimates lie within 2 m; at `EP2018` and `SSMT2024` they are
  within 0.12 m.
- `MNPK2018` plot 0200 is still on the edge of the search window, and its
  second alignment, at 0.812, fails the first check too.

## Disturbance between survey and flight

| Plot | Project | Group | Flight admitted | Interval | Fire records | Fire clear | Activity records | National Forest land | Activities clear | Test stems | Missing | Missing share | Canopy | Cleared | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0068 | EP2018 | A | yes | 2019-01-01 to 2022-08-19 | 0 | yes | 0 | no | yes | 922 | — | — | not_run | no | presence_not_run |
| 0084 | JLHZ2019 | A | yes | 2019-01-01 to 2022-06-10 | 0 | yes | 0 | yes | yes | 115 | — | — | not_run | no | presence_not_run |
| 0085 | JLHZ2019 | A | yes | 2020-01-01 to 2022-11-03 | 0 | yes | 0 | no | yes | 711 | — | — | not_run | no | presence_not_run |
| 0086 | JLHZ2019 | A | yes | 2020-01-01 to 2022-11-03 | 0 | yes | 0 | no | yes | 744 | — | — | not_run | no | presence_not_run |
| 0277 | SSMT2024 | A | no | — | — | — | — | no | — | 458 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0278 | SSMT2024 | A | no | — | — | — | — | no | — | 97 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0279 | SSMT2024 | A | no | — | — | — | — | no | — | 36 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0280 | SSMT2024 | A | no | — | — | — | — | no | — | 351 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0281 | SSMT2024 | A | no | — | — | — | — | no | — | 469 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0282 | SSMT2024 | A | yes | 2021-01-01 to 2022-08-03 | 0 | yes | 0 | no | yes | 464 | — | — | not_run | no | presence_not_run |
| 0283 | SSMT2024 | A | yes | 2021-01-01 to 2021-07-06 | 0 | yes | 0 | no | yes | 452 | — | — | not_run | no | presence_not_run |
| 0284 | SSMT2024 | A | no | — | — | — | — | no | — | 199 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0285 | SSMT2024 | A | no | — | — | — | — | yes | — | 91 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0069 | STEF2007 | B | no | 2016-01-01 to 2021-11-21 | 0 | yes | 0 | yes | yes | 702 | — | — | not_run | no | presence_not_run |
| 0070 | STEF2007 | B | no | 2008-01-01 to 2022-06-14 | 0 | yes | 0 | yes | yes | 1,048 | — | — | not_run | no | presence_not_run |
| 0071 | STEF2007 | B | no | 2008-01-01 to 2022-06-14 | 0 | yes | 0 | yes | yes | 956 | — | — | not_run | no | presence_not_run |
| 0072 | STEF2007 | B | no | 2007-01-01 to 2021-11-21 | 0 | yes | 4 | yes | no | 987 | — | — | not_run | no | activity;presence_not_run |
| 0073 | STEF2018 | B | yes | 2018-01-01 to 2022-06-14 | 0 | yes | 0 | yes | yes | 283 | — | — | not_run | no | presence_not_run |
| 0074 | STEF2018 | B | yes | 2018-01-01 to 2022-06-14 | 0 | yes | 0 | yes | yes | 333 | — | — | not_run | no | presence_not_run |
| 0075 | STEF2018 | B | yes | 2018-01-01 to 2022-06-14 | 0 | yes | 0 | yes | yes | 397 | — | — | not_run | no | presence_not_run |
| 0076 | STEF2018 | B | yes | 2018-01-01 to 2022-06-14 | 0 | yes | 0 | yes | yes | 291 | — | — | not_run | no | presence_not_run |
| 0077 | STEF2018 | B | yes | 2018-01-01 to 2022-06-14 | 0 | yes | 5 | yes | no | 267 | — | — | not_run | no | activity;presence_not_run |
| 0078 | STEF2018 | B | yes | 2018-01-01 to 2022-06-14 | 0 | yes | 3 | yes | no | 232 | — | — | not_run | no | activity;presence_not_run |
| 0079 | STEF2018 | B | no | 2018-01-01 to 2022-06-14 | 0 | yes | 3 | yes | no | 357 | — | — | not_run | no | activity;presence_not_run |
| 0080 | STEF2018 | B | yes | 2018-01-01 to 2022-06-14 | 0 | yes | 4 | yes | no | 313 | — | — | not_run | no | activity;presence_not_run |
| 0081 | SJGEO2018 | B | no | 2019-01-01 to 2018-08-03 | — | — | — | yes | — | 448 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0197 | MNPK2018 | B | yes | 2018-01-01 to 2022-06-15 | 0 | yes | 0 | yes | yes | 80 | — | — | not_run | no | presence_not_run |
| 0198 | MNPK2018 | B | yes | 2018-01-01 to 2022-06-15 | 0 | yes | 0 | yes | yes | 50 | — | — | not_run | no | presence_not_run |
| 0199 | MNPK2018 | B | yes | 2018-01-01 to 2022-06-15 | 0 | yes | 0 | yes | yes | 104 | — | — | not_run | no | presence_not_run |
| 0200 | MNPK2018 | B | yes | 2018-01-01 to 2022-06-15 | 0 | yes | 0 | yes | yes | 33 | — | — | not_run | no | presence_not_run |
| 0201 | MNPK2018 | B | yes | 2018-01-01 to 2022-06-15 | 0 | yes | 0 | yes | yes | 73 | — | — | not_run | no | presence_not_run |
| 0202 | MNPK2018 | B | yes | 2018-01-01 to 2022-06-15 | 0 | yes | 0 | yes | yes | 53 | — | — | not_run | no | presence_not_run |
| 0270 | OHDS2024 | B | no | 2019-01-01 to 2013-11-28 | — | — | — | yes | — | 503 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0271 | OHDS2024 | B | no | — | — | — | — | yes | — | 336 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0272 | OHDS2024 | B | no | — | — | — | — | yes | — | 316 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0273 | OHDS2024 | B | no | — | — | — | — | yes | — | 193 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0274 | OHDS2024 | B | no | — | — | — | — | yes | — | 361 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0275 | OHDS2024 | B | no | — | — | — | — | yes | — | 237 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0276 | OHDS2024 | B | no | — | — | — | — | yes | — | 217 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0286 | DS2024 | B | no | — | — | — | — | no | — | 8 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0287 | DS2024 | B | no | 2013-01-01 to 2021-03-31 | 0 | yes | 0 | no | yes | 72 | — | — | not_run | no | presence_not_run |
| 0288 | DS2024 | B | no | 2013-01-01 to 2021-03-31 | 0 | yes | 0 | no | yes | 148 | — | — | not_run | no | presence_not_run |
| 0289 | DS2024 | B | no | — | — | — | — | no | — | 203 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |
| 0290 | DS2024 | B | no | 2013-01-01 to 2021-03-31 | 0 | yes | 0 | no | yes | 51 | — | — | not_run | no | presence_not_run |
| 0291 | DS2024 | B | no | — | — | — | — | no | — | 252 | — | — | not_run | no | fire_unchecked;activity_unchecked;presence_not_run |

- **Fire.** No fire perimeter lies within 50 m of any of the 19 plots with
  an admitted flight inside its interval. The nearest inside an interval is
  the Dexter fire of 2021, 97 m from `MNPK2018` plot 0198.
- **Forest Service activities.** `STEF2018` plots 0077, 0078 and 0080 have
  completed activities inside their interval: pile burning in January 2018,
  a salvage cut in June 2018 and, at 0077, a commercial thin in November
  2020. They are held on evidence. The survey is dated only by its year, so
  the 2018 activities may predate it; the declared interval starts on
  1 January and counts them.
- **Record coverage.** The activity records cover National Forest land.
  `EP2018`, the two northern `JLHZ2019` plots and the two `SSMT2024` plots
  lie outside it and pass that check for lack of a record source.
- **Canopy over mapped trees.** Not run: it is made at registered
  positions, and no plot is registered.
- **Leaf-off.** `JLHZ2019` plots 0085 and 0086 remain held by the first
  protocol's rule.
- **Reversed intervals.** At `SJGEO2018` plot 0081 and `OHDS2024` plot 0270
  the last flight predates the survey year, so the interval ends before it
  starts and no record check can be made. Neither has an admitted flight.

| Plot | Fire records in the interval | Activity records in the interval |
| --- | --- | --- |
| 0072 | — | Burning of Piled Material (2008-11-01, fuels_fire); Burning of Piled Material (2018-01-23, fuels_fire); Salvage Cut (intermediate treatment, not regeneration) (2018-06-01, fuels_mechanical); Salvage Cut (intermediate treatment, not regeneration) (2018-06-01, harvest_2011_2020) |
| 0077 | — | Burning of Piled Material (2018-01-23, fuels_fire); Commercial Thin (2020-11-20, fuels_mechanical); Commercial Thin (2020-11-20, harvest_2021_current); Salvage Cut (intermediate treatment, not regeneration) (2018-06-01, fuels_mechanical); Salvage Cut (intermediate treatment, not regeneration) (2018-06-01, harvest_2011_2020) |
| 0078 | — | Burning of Piled Material (2018-01-23, fuels_fire); Salvage Cut (intermediate treatment, not regeneration) (2018-06-01, fuels_mechanical); Salvage Cut (intermediate treatment, not regeneration) (2018-06-01, harvest_2011_2020) |
| 0079 | — | Burning of Piled Material (2018-01-23, fuels_fire); Salvage Cut (intermediate treatment, not regeneration) (2018-06-01, fuels_mechanical); Salvage Cut (intermediate treatment, not regeneration) (2018-06-01, harvest_2011_2020) |
| 0080 | — | Burning of Piled Material (2018-01-16, fuels_fire); Burning of Piled Material (2018-01-23, fuels_fire); Salvage Cut (intermediate treatment, not regeneration) (2018-06-01, fuels_mechanical); Salvage Cut (intermediate treatment, not regeneration) (2018-06-01, harvest_2011_2020) |

| Plot | Source | Fire | Date | In the interval | Within 50 m | Distance to the polygon, m |
| --- | --- | --- | --- | --- | --- | --- |
| 0084 | fire_history | SCHAUBACH | 1956 | no | no | 428 |
| 0084 | fire_history | HIGHWAY 41 Burn | 2019 | yes | no | 808 |
| 0084 | fire_history | O'NEAL | 1956 | no | no | 873 |
| 0084 | fire_history | MCDOUGAL | 1955 | no | no | 873 |
| 0084 | fire_history | EXP RANGE | 1952 | no | no | 873 |
| 0084 | fire_history | O'NEAL | 1950 | no | no | 873 |
| 0084 | fire_history | SCHAUBACH | 1975 | no | no | 921 |
| 0197 | fire_history | CLARK | 2016 | no | yes | 0 |
| 0197 | fire_wfigs | Dexter | 2021-07-12 | yes | no | 138 |
| 0197 | fire_history | Unknown | 1986 | no | no | 855 |
| 0197 | fire_history | SPRINGS | 2019 | yes | no | 914 |
| 0198 | fire_history | CLARK | 2016 | no | yes | 0 |
| 0198 | fire_wfigs | Dexter | 2021-07-12 | yes | no | 97 |
| 0198 | fire_history | Unknown | 1986 | no | no | 722 |
| 0199 | fire_history | CLARK | 2016 | no | yes | 0 |
| 0199 | fire_wfigs | Dexter | 2021-07-12 | yes | no | 275 |
| 0199 | fire_history | SPRINGS | 2019 | yes | no | 824 |
| 0199 | fire_history | Unknown | 1986 | no | no | 910 |
| 0200 | fire_history | OHAREL | 2007 | no | yes | 0 |
| 0201 | fire_history | OHAREL | 2007 | no | yes | 0 |
| 0202 | fire_history | OHAREL | 2007 | no | yes | 0 |

## Gates, cells and reference stems

| Group | Step | Gate | Failing this gate, at any step | Removed at this step | Plots left |
| --- | --- | --- | --- | --- | --- |
| A | 0 | plots | — | — | 13 |
| A | 1 | screen_ok | 0 | 0 | 13 |
| A | 2 | flight_admitted | 7 | 7 | 6 |
| A | 3 | geometry_consistent | 0 | 0 | 6 |
| A | 4 | conditions_admitted | 13 | 6 | 0 |
| A | 5 | registered | 13 | 0 | 0 |
| A | — | admitted | — | — | 0 |
| B | 0 | plots | — | — | 32 |
| B | 1 | screen_ok | 0 | 0 | 32 |
| B | 2 | flight_admitted | 19 | 19 | 13 |
| B | 3 | geometry_consistent | 4 | 0 | 13 |
| B | 4 | conditions_admitted | 32 | 13 | 0 |
| B | 5 | registered | 32 | 0 | 0 |
| B | — | admitted | — | — | 0 |
| all groups | 0 | plots | — | — | 45 |
| all groups | 1 | screen_ok | 0 | 0 | 45 |
| all groups | 2 | flight_admitted | 26 | 26 | 19 |
| all groups | 3 | geometry_consistent | 4 | 0 | 19 |
| all groups | 4 | conditions_admitted | 45 | 19 | 0 |
| all groups | 5 | registered | 45 | 0 | 0 |
| all groups | — | admitted | — | — | 0 |

Every plot fails the conditions gate, because the canopy check could not
run. For 38 of the 45 that failure is an unmade check and not evidence;
seven fail on evidence.

| Group | Project | Plots admitted | Cells | Headline cells | Relaxed cells | Reference stems in plots | In cells | In headline cells | Plot area, ha | Cell area, ha | Cells of registered plots | Headline cells of registered plots | Cells of provisionally placed plots | Headline cells of provisionally placed plots | Reference stems in those headline cells |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A | EP2018 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0.00 | 0.00 | 0 | 0 | 15 | 15 | 1,124 |
| A | JLHZ2019 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0.00 | 0.00 | 0 | 0 | 0 | 0 | 0 |
| A | SSMT2024 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0.00 | 0.00 | 0 | 0 | 8 | 8 | 841 |
| A | all projects | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0.00 | 0.00 | 0 | 0 | 23 | 23 | 1,965 |
| B | DS2024 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0.00 | 0.00 | 0 | 0 | 0 | 0 | 0 |
| B | MNPK2018 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0.00 | 0.00 | 0 | 0 | 20 | 20 | 382 |
| B | OHDS2024 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0.00 | 0.00 | 0 | 0 | 0 | 0 | 0 |
| B | SJGEO2018 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0.00 | 0.00 | 0 | 0 | 0 | 0 | 0 |
| B | STEF2007 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0.00 | 0.00 | 0 | 0 | 0 | 0 | 0 |
| B | STEF2018 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0.00 | 0.00 | 0 | 0 | 73 | 72 | 1,633 |
| B | all projects | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0.00 | 0.00 | 0 | 0 | 93 | 92 | 2,015 |

The last three columns count cells of plots placed provisionally at the
method's estimate, only so that the hold rule can be evaluated. They include
the three `STEF2018` plots with activity records, which are not eligible
for the hold; the hold counts 9 plots and 1,449 stems in group B.

## Limits

- Five units per signal is a small sample. All five agree with the truth,
  which is encouraging and is not a pass.
- Only one of the six units that erred the same way under both signals in
  the first protocol has a credible truth here (`ABBY_063`). The others
  stay unexplained.
- The crown truth rests on boxes drawn on camera images, and a box centre
  is not a treetop.
- The benchmark units' estimates were known before this protocol was
  written; their truths were not. The NIWO units were entirely new.
- NIWO lies outside California and Oregon and was used only as test data.
- Its clips have 4 to 12 returns per m², sparser than the 3DEP flights of
  the catalogue plots.
- Fire and activity records miss events outside their coverage.

## Reproduce

```sh
export CLAUDE_JOB_DIR=$(pwd)/work
Rscript scripts/preflight_ofo_crowntruth.R STAGE=fetch \
  COMMIT=96b29d566ca7ea9f604de3e1235c503ab101cb8a
Rscript scripts/preflight_ofo_niwo.R STAGE=reference
Rscript scripts/preflight_ofo_niwo.R STAGE=lidar
Rscript scripts/preflight_ofo_niwo.R STAGE=clips
Rscript scripts/preflight_ofo_niwo.R STAGE=register CORES=8
Rscript scripts/preflight_ofo_crowntruth.R STAGE=truth CORES=8
Rscript scripts/preflight_ofo_crowntruth.R STAGE=evaluate
Rscript scripts/preflight_ofo_disturbance.R STAGE=records
Rscript scripts/preflight_ofo_disturbance.R STAGE=presence
Rscript scripts/preflight_ofo2_assemble.R
Rscript scripts/report_ofo_preflight2.R
```

The NIWO stages need a NEON API token in `NEON_TOKEN`. They and the
crown-truth stage read the sealed NEON root and write nothing there.
