# Open Forest Observatory stem maps: preflight results

Checked on 17 November 2026. This preflight asks whether stem maps of the
[Open Forest Observatory data catalog](https://doi.org/10.5281/zenodo.23402904),
paired with public USGS 3DEP point clouds, can extend the benchmark's field
reference. It follows the [preflight protocol](../docs/ofo-preflight-protocol.md),
which was written first. It is score-blind: no detector was run on these
plots and nothing was scored.

**Decision: no-go for all four plot groups.** The stem maps must be shifted
onto the LiDAR before they can be matched at 4 m, and no registration method
passed its known-truth test. The declared method failed. The protocol was
then amended to allow one redesign, and that redesign failed its
confirmation. No reference table was written, no clip was frozen and no
detector was run. The NEON results are untouched. A
[second preflight](ofo-preflight-2-results.md) for groups A and B followed
under a new protocol and ended in hold on that preflight's reading of its
protocol, or no-go on a strict reading. The study was closed there on
18 November 2026; the catalogue's stem maps are not part of the benchmark's
reference.

The other findings matter for any later attempt:

- **Public LiDAR is there.** 169 of the 225 non-NEON plots have an
  admitted flight: quality level 1, within four years of the survey and
  covering the plot. Their median density is 32.6 returns/m²
  (17.9 first returns/m²), about twice that of the NEON clouds.
- **The registration test fails at one site more than anywhere.** Every
  accepted Wind River unit is within 2 m of the truth, and none of the six
  accepted Abby Road units under the height signal is. Three Abby Road
  plots, and a composite made mostly of two of them, have their stems about
  3 m south of their canopy under both signals. The test cannot tell a real
  offset of those NEON stem maps from a fault of the method. Without Abby
  Road both signals still fall short of the pass rule, the height signal
  narrowly.
- **The drone check cannot cover most of groups A and B.** For 18 of their
  19 plots with an admitted flight the drone mission was flown after the
  3DEP flight, so comparing the two says nothing about the years between
  survey and flight. Only the `EP2018` plot has a mission on the survey
  side.
- **The 14 `OHDS2024` and `SSMT2024` plots without an admitted flight are
  covered elsewhere.** Public tiles or state collections exist for all of
  them. None was acquired. The six `DS2024` plots, which have no admitted
  flight either, were not searched.

## Decision

| Group | Decision | Signal | Signal admitted | Plots admitted | Plots with headline cells | Reference stems in headline cells | Group floor, cm | Reasons |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A | no-go | height | no | 0 | 0 | 0 | 10.0 | signal height not admitted; 0 admitted plots (need 3), 0 with a headline cell; 0 reference stems in their headline cells (need 100); no admitted plot whose licence to check |
| B | no-go | rank | no | 0 | 0 | 0 | 10.0 | signal rank not admitted; 0 admitted plots (need 3), 0 with a headline cell; 0 reference stems in their headline cells (need 100); no admitted plot whose licence to check |
| C | no-go | height | no | 0 | 0 | 0 | — | signal height not admitted; 0 admitted plots (need 3), 0 with a headline cell; 0 reference stems in their headline cells (need 100); no admitted plot whose licence to check |
| D | no-go | rank | no | 0 | 0 | 0 | — | signal rank not admitted; 0 admitted plots (need 3), 0 with a headline cell; 0 reference stems in their headline cells (need 100); no admitted plot whose licence to check |

A group needs an admitted registration signal, at least three admitted
plots and at least 100 reference stems in its headline cells. No signal was
admitted, so no plot was registered and every count behind the decision is
zero. The protocol allows no further redesign of the registration, so a new
attempt needs a new protocol. Two things would have to change in it:

- a known-truth test that does not rest on NEON plot positions alone, or
  independent evidence on the stem-map positions of the units that err the
  same way under both signals (the Abby Road units, `SOAP_031` and
  `TEAK_046`, described below);
- a disturbance source that covers the years between survey and flight for
  groups A and B.

## What was run

| Stage | Script | Writes under `<job>/ofo` |
| --- | --- | --- |
| Catalogue, flights, clouds, geometry, licences | [preflight_ofo_catalog.R](../scripts/preflight_ofo_catalog.R) | `sources/`, `lidar-index/`, `clouds/`, plot, tree, flight and geometry tables |
| Registration and its tests | [preflight_ofo_registration.R](../scripts/preflight_ofo_registration.R) | Known-truth, development, confirmation and catalogue tables, test record |
| Disturbance, snow, leaf-off | [preflight_ofo_conditions.R](../scripts/preflight_ofo_conditions.R) | Conditions table, snow grids |
| Collections for uncovered plots | [preflight_ofo_state_lidar.R](../scripts/preflight_ofo_state_lidar.R) | Collection table and request log |
| Cells, admission, decision | [preflight_ofo_decision.R](../scripts/preflight_ofo_decision.R) | Cell, admission, summary and decision tables |
| Reference tables of go groups | [prepare_ofo_reference.R](../scripts/prepare_ofo_reference.R) | Nothing here: no group is go |
| Tables of this report | [report_ofo_preflight.R](../scripts/report_ofo_preflight.R) | `preflight/report_tables.md` |

Every table below is copied from the output of the last script. Retrieval
times and digests of the inputs are in
[ofo-preflight-sources.json](../docs/ofo-preflight-sources.json).

## Catalogue and plot groups

The catalogue holds 287 plots and 64,295 trees in 21 projects. The 62 plots
of project `NEON2023` are NEON plots already in the benchmark and are left
out. Of the other 225, the screen removes 28 nested hyperplots, 14 plots
tallied by height alone and 11 without live or dead status. The remaining
172 fall into the four groups of the protocol.

| Group | Projects (plots) | Plots | Plots with an admitted flight | Reference stems in them |
| --- | --- | --- | --- | --- |
| A | EP2018 (1), JLHZ2019 (3), SSMT2024 (9) | 13 | 6 | 6,282 |
| B | DS2024 (6), MNPK2018 (6), OHDS2024 (7), SJGEO2018 (1), STEF2007 (4), STEF2018 (8) | 32 | 13 | 3,212 |
| C | Eshom2020 (33), FOCAL2022 (4), FOCAL2023 (4), SSI2023 (1), TNC2023 (24), VP2022 (51) | 117 | 117 | 5,465 |
| D | CRBLDG2022 (4), Eshom2020 (6) | 10 | 10 | 963 |
| All groups | CRBLDG2022 (4), DS2024 (6), EP2018 (1), Eshom2020 (39), FOCAL2022 (4), FOCAL2023 (4), JLHZ2019 (3), MNPK2018 (6), OHDS2024 (7), SJGEO2018 (1), SSI2023 (1), SSMT2024 (9), STEF2007 (4), STEF2018 (8), TNC2023 (24), VP2022 (51) | 172 | 146 | 15,922 |

Reference stems are live trees inside the plot polygon at or above the
plot's gate: 10 cm diameter in groups A and B, the plot's own floor in C and
D. Group C plots are complete only from 25.0 to 25.4 cm upward, or from
12.7 cm in the small `Eshom2020` plots. Six `Eshom2020` plots of group D
hold no live stem. The counts are stems inside the plot polygon; the
appendix lists every plot.

## Flights and density

211 of the 225 plots lie inside at least one public 3DEP Entwine resource
of quality level 2 or better, and 209 returned points. Flight dates come
from the GPS times of the returns inside each plot. 169 plots have
an admitted flight: 146 of the 172 grouped plots and
23 of the others.

| Project | Plots | Selected work unit(s) (plots) | Quality level (plots) | Flight months | Gap, years | All returns per m², median (range) | First returns per m², median (range) | Plots with an admitted flight | Other plots by reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CRBLDG2022 | 4 | CA_SierraNevada_2_2022 (4) | QL 1 (4) | 2021-11 | 1 | 47.3 (32.8–61.8) | 21.0 (17.0–24.5) | 4 | — |
| Cambria2021 | 28 | CA_FEMA_Z4_B2_2018 (28) | QL 2 (28) | 2018-01 | 3 | 6.1 (2.3–18.2) | 4.5 (2.2–8.8) | 0 | quality_level (28) |
| DS2024 | 6 | WA_ThurstonCo_1_2021 (5) | QL 1 (5) | 2021-03 | 8 | 31.9 (25.5–36.4) | 17.7 (14.6–21.7) | 0 | gap (3), no_public_cloud (3) |
| EP2018 | 1 | CA_SierraNevada_5_2022 (1) | QL 1 (1) | 2022-06 | 3 | 19.3 (19.3) | 10.8 (10.8) | 1 | — |
| Eshom2020 | 39 | CA_SierraNevada_14_B22 (39) | QL 1 (39) | 2022-06 | 0, 1 | 26.7 (15.3–49.9) | 19.1 (13.3–20.7) | 39 | — |
| FOCAL2020 | 10 | CA_CarrHirzDeltaFires_1_2019 (3), CA_NoCAL_Wildfires_B4_2018 (2), CA_NorthCoastRanges_2_B23 (1), CA_SierraNevada_11_B22 (2), CA_SierraNevada_4_2022 (2) | QL 1 (8), QL 2 (2) | 2019-04, 2019-08, 2019-10, 2021-11, 2022-06, 2023-09 | 1, 2, 3 | 34.2 (7.1–45.1) | 18.4 (4.8–23.6) | 8 | quality_level (2) |
| FOCAL2022 | 4 | CA_SierraNevada_4_2022 (4) | QL 1 (4) | 2021-11 | 0 | 35.3 (32.9–49.1) | 15.2 (14.8–20.8) | 4 | — |
| FOCAL2023 | 4 | CA_SierraNevada_2_2022 (1), CA_SierraNevada_5_2022 (3) | QL 1 (4) | 2021-11 | 2 | 32.3 (24.6–33.2) | 19.6 (12.8–22.4) | 4 | — |
| FOCAL2025 | 4 | CA_SierraNevada_2_2022 (1), CA_SierraNevada_5_2022 (3) | QL 1 (4) | 2021-11 | 4 | 32.3 (22.8–42.9) | 16.8 (12.1–24.4) | 4 | — |
| JLHZ2019 | 3 | CA_NorthernCA_5_B22 (2), CA_SierraNevada_11_B22 (1) | QL 1 (3) | 2022-06, 2022-10 | 2, 3 | 69.6 (15.1–113.1) | 43.2 (11.0–58.4) | 3 | — |
| MNPK2018 | 6 | CA_SierraNevada_13_B22 (6) | QL 1 (6) | 2022-06 | 4 | 25.7 (23.1–30.6) | 19.5 (15.7–21.2) | 6 | — |
| OHDS2024 | 7 | WA_Olympic_Peninsula_2013 (1) | QL 1 (1) | 2013-11 | 6 | 11.7 (11.7) | 8.7 (8.7) | 0 | gap (1), no_public_cloud (6) |
| SJGEO2018 | 1 | CA_SoCal_Wildfires_B1_2018 (1) | QL 2 (1) | 2018-07 | 1 | 13.5 (13.5) | 9.7 (9.7) | 0 | quality_level (1) |
| SSI2023 | 1 | CA_SierraNevada_2_2022 (1) | QL 1 (1) | 2021-11 | 2 | 36.4 (36.4) | 12.9 (12.9) | 1 | — |
| SSMT2024 | 9 | OR_McKenzieRiver_1_2021 (1), OR_WWildfires_1_A22 (1) | QL 1 (2) | 2021-07, 2022-08 | 0, 1 | 22.5 (20.4–24.5) | 12.0 (10.1–14.0) | 2 | no_public_cloud (7) |
| STEF2007 | 4 | CA_SierraNevada_11_B22 (2), CA_SierraNevada_5_2022 (1), CA_SierraNevada_8_2022 (1) | QL 1 (4) | 2021-11, 2022-06 | 5, 14 | 28.9 (15.6–43.0) | 15.8 (7.2–18.4) | 0 | gap (3), gap;coverage (1) |
| STEF2018 | 8 | CA_SierraNevada_11_B22 (7), CA_SierraNevada_8_2022 (1) | QL 1 (8) | 2021-11, 2022-06 | 3, 4 | 23.4 (17.8–24.9) | 15.2 (12.3–15.9) | 7 | coverage (1) |
| TNC2023 | 24 | CA_SierraNevada_1_2022 (2), CA_SierraNevada_4_2022 (20), CA_SierraNevada_6_2022 (2) | QL 1 (24) | 2021-11, 2022-07 | 1, 2 | 38.1 (24.1–52.7) | 17.0 (12.1–23.8) | 24 | — |
| VP2022 | 51 | CA_NoCAL_Wildfires_PlumasNF_B2_2018 (1), CA_SierraNevada_1_2022 (5), CA_SierraNevada_4_2022 (21), CA_SierraNevada_5_2022 (6), CA_SierraNevada_6_2022 (18) | QL 1 (51) | 2018-08, 2021-11, 2022-06, 2022-08 | 0, 1, 4 | 33.1 (14.2–50.1) | 16.6 (10.2–24.4) | 51 | — |
| WADNR2023 | 11 | WA_CentralWildfire_1_D22 (10), WA_CentralWildfire_2_D22 (1) | QL 1 (11) | 2022-09, 2022-10 | 1 | 22.2 (15.2–50.8) | 16.3 (11.0–28.5) | 11 | — |
| All non-NEON plots | 225 | 22 work units | QL 1 (180), QL 2 (31) | 2013-11 to 2023-09 | 0, 1, 2, 3, 4, 5, 6, 8, 14 | 29.5 (2.3–113.1) | 16.8 (2.2–58.4) | 169 | coverage (1), gap (7), gap;coverage (1), no_public_cloud (16), quality_level (31) |
| Admitted flights | 169 | 16 work units | QL 1 (169) | 2018-08 to 2023-09 | 0, 1, 2, 3, 4 | 32.6 (14.2–113.1) | 17.9 (10.1–58.4) | 169 | — |
| NEON WREF (quoted) | — | — | — | — | — | median 17.9, range 10.2–25.8 (9 tower plots) | median 9.8, range 5.3–15.2 | — | — |
| NEON ABBY (quoted) | — | — | — | — | — | median 17.1, range 12.5–19.5 (7 tower plots) | median 9.6, range 7.0–11.0 | — | — |
| NEON D17, for comparison (quoted) | — | — | — | — | — | median 18.2, range 6.6–25.4 (46 swept plots) | median 11.5, range 4.2–17.8 | — | — |

- **Density.** The admitted flights are about twice as dense as the NEON
  2021 clouds, so the native rung would not be comparable across sources.
  No admitted flight is below 8 returns/m², in all returns or in first
  returns, so no plot would lose a rung of the ladder.
- **Flights not admitted.** 31 plots have only quality level 2 flights
  (`Cambria2021`, two `FOCAL2020` plots, `SJGEO2018`). Nine fail the
  four-year gap or the coverage rule. 16 have no usable public cloud: 14
  outside every Entwine resource and two `DS2024` plots whose resource
  returned no points.
- **Noise and withheld returns.** The catalogue check of 16 November kept
  returns of classes 7 and 18, because its PDAL range filter joins ranges on
  one dimension with "or" and so dropped nothing. This stage drops them with
  an expression filter and stops if any remains. It also drops returns
  flagged withheld, under the protocol's second amendment. Most plots
  have no withheld return, but 18 plots with an admitted flight have more
  than 10% and plot 0226 has 41%; the table below gives the shares.
- **Flight dates.** Clouds are stored in LAS point format 1. Writing
  compressed point formats 6 to 10 corrupted the GPS times of the first
  chunk whenever it held returns 12 hours or more apart.

| Flights | Plots | Median withheld share | Maximum (plot) | Plots above 10% |
| --- | --- | --- | --- | --- |
| Plots with a cloud | 209 | 0.0% | 41.3% (0226) | 19 |
| Admitted flights | 169 | 0.0% | 41.3% (0226) | 18 |

## Geometry

| Project | Plots | Trees | Stems outside the polygon | Plots failing the 95% rule | Failing plots (reference stems within 1 m) | Plots without reference stems | Duplicate positions | Plots overlapping another | Coordinate step, m |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CRBLDG2022 | 4 | 1,158 | 0.0% | 0 | — | 0 | 0 | 0 | <0.1 |
| Cambria2021 | 28 | 786 | 2.2% | 0 | — | 7 | 2 | 28 | 0.1 |
| DS2024 | 6 | 2,935 | 5.6% | 0 | — | 0 | 2 | 0 | <0.1 |
| EP2018 | 1 | 2,132 | 0.0% | 0 | — | 0 | 0 | 0 | <0.1 |
| Eshom2020 | 39 | 247 | 3.2% | 2 | 0205 (0.0%), 0221 (90.0%) | 6 | 0 | 0 | <0.1 |
| FOCAL2020 | 10 | 2,595 | 0.2% | 0 | — | 10 | 4 | 0 | <0.1 |
| FOCAL2022 | 4 | 206 | 0.5% | 0 | — | 0 | 0 | 0 | <0.1 |
| FOCAL2023 | 4 | 160 | 16.2% | 1 | 0167 (21.4%) | 0 | 0 | 0 | <0.1 |
| FOCAL2025 | 4 | 459 | 0.7% | 0 | — | 0 | 1 | 0 | <0.1 |
| JLHZ2019 | 3 | 4,389 | 0.0% | 0 | — | 0 | 14 | 0 | <0.1 |
| MNPK2018 | 6 | 1,010 | 1.5% | 0 | — | 0 | 10 | 0 | <0.1 |
| NEON2023 | 62 | 2,005 | 1.4% | 0 | — | 3 | 0 | 0 | — |
| OHDS2024 | 7 | 5,872 | 9.6% | 4 | 0271 (76.7%), 0272 (92.9%), 0273 (91.2%), 0275 (80.2%) | 0 | 4,320 | 0 | 75.1 |
| SJGEO2018 | 1 | 4,250 | 0.4% | 0 | — | 0 | 11 | 0 | <0.1 |
| SSI2023 | 1 | 195 | 0.0% | 0 | — | 0 | 9 | 0 | <0.1 |
| SSMT2024 | 9 | 7,998 | 0.5% | 0 | — | 0 | 0 | 0 | <0.1 |
| STEF2007 | 4 | 12,801 | 0.5% | 0 | — | 0 | 1 | 0 | <0.1 |
| STEF2018 | 8 | 3,492 | 0.4% | 0 | — | 0 | 0 | 0 | <0.1 |
| TNC2023 | 24 | 3,347 | 0.4% | 0 | — | 0 | 9 | 1 | <0.1 |
| VP2022 | 51 | 7,168 | 1.0% | 1 | 0018 (93.8%) | 0 | 5 | 1 | <0.1 |
| WADNR2023 | 11 | 1,090 | 0.7% | 0 | — | 11 | 2 | 0 | 0.1 |
| All non-NEON projects | 225 | 62,290 | 1.7% | 8 | — | 34 | 4,390 | 30 | 75.1 |
| Whole catalogue | 287 | 64,295 | 1.7% | 8 | — | 37 | 4,390 | 30 | 75.1 |

Eight plots fail the rule that 95% of reference stems lie within 1 m
of the polygon. `OHDS2024` stores longitude to 0.001°, a step of about 75 m,
and has 4,320 duplicate positions; its stem maps cannot be used as mapped.
The protocol's rule catches four of its seven plots, not the cause. `VP2022`
plot 0049 overlaps `TNC2023` plot 0110.

## Registration

The catalogue states that its ground plots are not necessarily
co-registered with the drone missions that cover them, and should lie
within about 10 m of them. Each plot therefore needs one rigid shift,
estimated without any detector. The test of a method uses NEON plots, whose
stems and clouds share a frame: the stems are displaced by a known offset
and the method must undo it.

### The declared method

The declared method compared stem heights, or diameter ranks, with a
smoothed canopy top at each stem. It failed for both signals.

| Signal | Plots | Run | Accepted | Median error of accepted, m | Accepted within 2 m | Result |
| --- | --- | --- | --- | --- | --- | --- |
| height | 106 | 30 | 8 | 1.9 | 50.0% (4 of 8) | fail |
| rank | 106 | 64 | 5 | 2.9 | 20.0% (1 of 5) | fail |
| Pass rule | — | — | at least 20 | at most 1.0 | at least 90.0% | — |

Under the height signal the plots the gate rejected were worse than those
it accepted. Under the diameter signal they had the lower median and more
plots within 2 m, but a far longer tail. Neither set came near the pass
rule, and errors did not fall clearly with the stem count:

| Signal | Accepted | Plots run | Median error, m | 90th percentile, m | Maximum, m | Within 2 m |
| --- | --- | --- | --- | --- | --- | --- |
| height | no | 22 | 2.7 | 5.2 | 10.7 | 8 (36.4%) |
| height | yes | 8 | 1.9 | 3.2 | 4.6 | 4 (50.0%) |
| rank | no | 59 | 2.2 | 13.0 | 21.6 | 27 (45.8%) |
| rank | yes | 5 | 2.9 | 3.7 | 3.8 | 1 (20.0%) |

| Signal | Signal stems | Run | Accepted | Median error of run plots, m | Median error of accepted plots, m |
| --- | --- | --- | --- | --- | --- |
| height | 15-29 | 22 | 4 | 2.5 | 2.2 |
| height | 30-59 | 8 | 4 | 2.1 | 1.5 |
| rank | 15-29 | 28 | 0 | 2.5 | — |
| rank | 30-59 | 28 | 3 | 3.2 | 3.7 |
| rank | 60+ | 8 | 2 | 1.7 | 1.9 |

Two faults were identified from this test. The objective was flat near its
top and ties went to the shortest shift, which pulled estimates toward zero.
And NEON plots hold few stems, so the test said little about plots of
catalogue size:

| Signal | Plots | At least 15 signal stems | At least 30 signal stems | At least 60 signal stems |
| --- | --- | --- | --- | --- |
| height | 106 | 30 | 8 | 0 |
| rank | 106 | 64 | 36 | 8 |

The protocol records both faults in its first amendment, written after this
test and before any redesign. One pattern of this first test went unnoticed
at the time: by site, the accepted plots with large errors were mostly at
Abby Road.

| Signal | Site | Plots | Run | Accepted | Median error of accepted, m | Accepted within 2 m |
| --- | --- | --- | --- | --- | --- | --- |
| height | ABBY | 25 | 10 | 6 | 2.2 | 2 |
| height | SJER | 6 | 0 | 0 | — | 0 |
| height | SOAP | 18 | 1 | 0 | — | 0 |
| height | TEAK | 19 | 3 | 0 | — | 0 |
| height | WREF | 38 | 16 | 2 | 1.7 | 2 |
| rank | ABBY | 25 | 22 | 4 | 3.2 | 1 |
| rank | SJER | 6 | 1 | 0 | — | 0 |
| rank | SOAP | 18 | 5 | 1 | 2.9 | 0 |
| rank | TEAK | 19 | 9 | 0 | — | 0 |
| rank | WREF | 38 | 27 | 0 | — | 0 |

### The redesign and its confirmation

The amendment split the 106 NEON plots into development and confirmation
halves. It added composites of three to five plots of one site, displaced
together, to test at catalogue stem counts. Thirty-four estimator variants
were compared on the development half; the best of each kind correlates a
map drawn from the stems with the canopy height raster.

| Signal | Variant | Units run | Median error, m | Share within 2 m |
| --- | --- | --- | --- | --- |
| height | ncc | 49 | 0.92 | 81.6% |
| height | ncc_r007 | 49 | 0.95 | 77.6% |
| height | ncc_mask3 | 49 | 0.96 | 77.6% |
| height | ncc_gauss0.5 | 49 | 0.96 | 81.6% |
| height | ncc_unit | 49 | 1.01 | 81.6% |
| height | ncc_centroid | 49 | 1.05 | 75.5% |
| height | ncc_mask5 | 49 | 1.05 | 79.6% |
| height | ncc_r2 | 49 | 1.05 | 75.5% |
| height | ncc_mask6 | 49 | 1.10 | 73.5% |
| height | ncc_r015 | 49 | 1.10 | 75.5% |
| height | kern_raw | 49 | 1.17 | 77.6% |
| height | kern_gauss0.5 | 49 | 1.19 | 75.5% |
| height | kern_max3 | 49 | 1.28 | 67.3% |
| height | kern_gauss1 | 49 | 1.46 | 61.2% |
| height | corr_gauss1 | 49 | 1.67 | 59.2% |
| height | corr_gauss1.5 | 49 | 1.72 | 59.2% |
| height | corr_raw | 49 | 2.05 | 49.0% |
| height | share_max5_peak | 49 | 2.17 | 46.9% |
| height | share_max5_centroid | 49 | 2.45 | 40.8% |
| rank | ncc_r007 | 50 | 0.91 | 74.0% |
| rank | ncc_unit | 50 | 0.96 | 74.0% |
| rank | ncc_sqrt | 50 | 0.96 | 74.0% |
| rank | ncc | 50 | 1.00 | 74.0% |
| rank | ncc_r004 | 50 | 1.02 | 74.0% |
| rank | ncc_mask3 | 50 | 1.07 | 76.0% |
| rank | ncc_r2 | 50 | 1.08 | 78.0% |
| rank | ncc_centroid | 50 | 1.09 | 72.0% |
| rank | ncc_mask5 | 50 | 1.11 | 70.0% |
| rank | ncc_r01 | 50 | 1.19 | 68.0% |
| rank | corr_gauss1.5 | 50 | 1.87 | 52.0% |
| rank | corr_gauss1 | 50 | 1.99 | 50.0% |
| rank | corr_raw | 50 | 2.19 | 46.0% |
| rank | corr_gauss2 | 50 | 2.53 | 42.0% |
| rank | corr_max5 | 50 | 2.79 | 34.0% |

The configuration frozen in the protocol did this on the development half:

| Signal | Variant | Gate | Smallest stem count | Units at or above it | Accepted | Median error of accepted, m | Accepted within 2 m |
| --- | --- | --- | --- | --- | --- | --- | --- |
| height | ncc | `sub_p90_m` at most 2.0 m | 20 | 46 | 31 | 0.73 | 30 (96.8%) |
| rank | ncc_r2 | `sub_p90_m` at most 1.0 m | 10 | 61 | 30 | 0.96 | 29 (96.7%) |

| Signal | Unit | Kind | Members | Site | Stems | Error, m | Error east, m | Error north, m | Residual, m | Stability, m |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| height | ABBY_062 | plot | — | ABBY | 71 | 3.05 | -0.26 | 3.04 | 0.15 | 0.06 |
| rank | ABBY_062 | plot | — | ABBY | 62 | 3.07 | -0.25 | 3.06 | 0.24 | 0.09 |

It was then run once on the confirmation half.

| Signal | Units | At or above the smallest stem count | Accepted | Median error of accepted, m | Accepted within 2 m | Result |
| --- | --- | --- | --- | --- | --- | --- |
| height | 67 | 39 (at least 20 stems) | 25 | 1.51 | 17 (68.0%) | fail |
| rank | 67 | 60 (at least 10 stems) | 35 | 0.76 | 26 (74.3%) | fail |
| Pass rule | — | — | at least 10 | at most 1.0 | at least 90.0% | — |

Both signals fail the 90% rule, and the height signal also fails the median
rule. The development figures did not carry over: 2,652 configurations had
been compared on 72 units.

| Kind | Variant | Signal | Units | Run | Median error of run, m | Accepted | Median error of accepted, m | Accepted within 2 m |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| plot | ncc | height | 51 | 49 | 1.6 | 14 | 1.9 | 7 (50.0%) |
| plot | ncc_r2 | rank | 51 | 51 | 2.2 | 23 | 0.8 | 16 (69.6%) |
| composite | ncc | height | 16 | 16 | 1.2 | 11 | 0.9 | 10 (90.9%) |
| composite | ncc_r2 | rank | 16 | 16 | 1.0 | 12 | 0.7 | 10 (83.3%) |

Composites do better than single plots. The height signal on composites
alone has 10 of 11 accepted units within 2 m. That is a reading after the
fact, not a pass: the rule was declared for all units together.

| Signal | Site | Accepted units | Median error, m | Within 2 m |
| --- | --- | --- | --- | --- |
| height | ABBY | 6 | 2.71 | 0 |
| height | SOAP | 2 | 2.13 | 1 |
| height | TEAK | 5 | 1.66 | 4 |
| height | WREF | 12 | 0.54 | 12 |
| rank | ABBY | 9 | 1.80 | 5 |
| rank | SJER | 1 | 13.21 | 0 |
| rank | SOAP | 3 | 2.37 | 1 |
| rank | TEAK | 6 | 1.01 | 4 |
| rank | WREF | 16 | 0.55 | 16 |

The failures cluster by site. All accepted Wind River units are within 2 m
under both signals. At Abby Road none of the six height units is.

| Signal | Unit | Kind | Members | Site | Stems | Error, m | Error east, m | Error north, m | Residual, m | Stability, m |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| height | ABBY_070 | plot | — | ABBY | 54 | 3.25 | -0.48 | 3.22 | 0.15 | 0.07 |
| height | ABBY_069 | plot | — | ABBY | 42 | 2.98 | -0.44 | 2.95 | 0.13 | 0.09 |
| height | C-ABBY_003 | composite | ABBY_003, ABBY_063, ABBY_069 | ABBY | 96 | 2.80 | -0.33 | 2.79 | 0.14 | 0.08 |
| height | SOAP_031 | plot | — | SOAP | 35 | 2.74 | 0.61 | -2.67 | 0.64 | 0.40 |
| height | ABBY_063 | plot | — | ABBY | 38 | 2.61 | -0.12 | 2.61 | 0.32 | 0.10 |
| height | TEAK_046 | plot | — | TEAK | 51 | 2.56 | 1.53 | -2.05 | 2.22 | 0.88 |
| height | ABBY_065 | plot | — | ABBY | 26 | 2.19 | -1.83 | -1.19 | 2.94 | 1.90 |
| height | ABBY_077 | plot | — | ABBY | 33 | 2.14 | 0.96 | -1.92 | 3.92 | 0.16 |
| rank | SJER_051 | plot | — | SJER | 14 | 13.21 | 11.92 | 5.69 | 0.75 | 0.30 |
| rank | TEAK_006 | plot | — | TEAK | 10 | 3.33 | -2.57 | 2.12 | 8.35 | 0.62 |
| rank | ABBY_070 | plot | — | ABBY | 53 | 3.22 | -0.43 | 3.19 | 0.21 | 0.08 |
| rank | ABBY_069 | plot | — | ABBY | 42 | 2.99 | -0.42 | 2.96 | 0.18 | 0.11 |
| rank | C-ABBY_003 | composite | ABBY_003, ABBY_063, ABBY_069 | ABBY | 89 | 2.75 | -0.29 | 2.73 | 0.28 | 0.12 |
| rank | C-SOAP_055 | composite | SOAP_055, SOAP_015, SOAP_031, SOAP_001, SOAP_049 | SOAP | 86 | 2.66 | 0.81 | -2.54 | 1.45 | 0.44 |
| rank | ABBY_063 | plot | — | ABBY | 32 | 2.61 | -0.10 | 2.61 | 0.29 | 0.13 |
| rank | SOAP_031 | plot | — | SOAP | 35 | 2.37 | 0.63 | -2.28 | 5.50 | 0.44 |
| rank | TEAK_046 | plot | — | TEAK | 51 | 2.22 | 1.22 | -1.86 | 2.32 | 0.78 |

Abby Road alone does not explain the failure. With one site left out at a
time, no row reaches the 90% rule: without Abby Road the height signal has
17 of 19 accepted units within 2 m and the diameter signal 21 of 26. This
too is a reading after the fact.

| Signal | Site left out | Accepted units | Median error, m | Within 2 m |
| --- | --- | --- | --- | --- |
| height | none | 25 | 1.51 | 17 (68.0%) |
| height | ABBY | 19 | 0.79 | 17 (89.5%) |
| height | SJER | 25 | 1.51 | 17 (68.0%) |
| height | SOAP | 23 | 0.92 | 16 (69.6%) |
| height | TEAK | 20 | 0.90 | 13 (65.0%) |
| height | WREF | 13 | 2.19 | 5 (38.5%) |
| rank | none | 35 | 0.76 | 26 (74.3%) |
| rank | ABBY | 26 | 0.66 | 21 (80.8%) |
| rank | SJER | 34 | 0.71 | 26 (76.5%) |
| rank | SOAP | 32 | 0.66 | 25 (78.1%) |
| rank | TEAK | 29 | 0.66 | 22 (75.9%) |
| rank | WREF | 19 | 1.87 | 10 (52.6%) |

The error is the estimated shift plus the known offset, so an error to
the north means the canopy lies north of the mapped stems. Six units appear
under both signals with nearly the same error: `ABBY_070`, `ABBY_069`,
`ABBY_063` and the composite `C-ABBY_003` about 3 m north, `SOAP_031` about
2.5 m south and `TEAK_046` about 2.4 m south-east. The composite is not
separate evidence: most of its stems come from `ABBY_063` and `ABBY_069`.
Development plot `ABBY_062` had shown the same 3 m to the north before the
freeze. `ABBY_070` is the plot that the protocol's corrections name as seen
before the split; it fell in the confirmation half and has the largest
height error there. The Abby Road units have residuals of about 0.3 m or less;
`SOAP_031` and `TEAK_046` do not, although the stability of all six is
below 1 m. NEON's stated position uncertainty for these plots is about
0.4 m.

A real offset between those stem maps and their canopy would look like
this. So would a fault shared by the two signals, which under this method
use the same surface and most of the same stems. The test cannot separate
the two, and the pass rule was applied as declared. Whether such offsets
affect the NEON benchmark at Abby Road, which matches at 4 m, was not
examined here.

### Catalogue plots under the frozen method

The frozen method was still run on every catalogue plot with a cloud, so
that shifts and residuals are on record. None of these is a registration:
no signal is admitted.

| Set | Group | Project | Method | Signal | Plots | Run | Accepted | Median shift of accepted, m | Median residual of run, m |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| candidate | A | EP2018 | amendment1 | height | 1 | 1 | 1 | 2.1 | 0.1 |
| candidate | A | EP2018 | amendment1 | rank | 1 | 1 | 1 | 1.9 | 0.1 |
| candidate | A | EP2018 | declared | height | 1 | 1 | 0 | — | 3.0 |
| candidate | A | EP2018 | declared | rank | 1 | 1 | 1 | 0.7 | 1.1 |
| candidate | A | JLHZ2019 | amendment1 | height | 3 | 3 | 3 | 1.6 | 1.3 |
| candidate | A | JLHZ2019 | amendment1 | rank | 3 | 3 | 1 | 1.3 | 2.3 |
| candidate | A | JLHZ2019 | declared | height | 3 | 3 | 1 | 0.0 | 3.0 |
| candidate | A | JLHZ2019 | declared | rank | 3 | 3 | 0 | — | 8.3 |
| candidate | A | SSMT2024 | amendment1 | height | 2 | 2 | 2 | 2.5 | <0.1 |
| candidate | A | SSMT2024 | amendment1 | rank | 2 | 2 | 2 | 2.5 | 0.1 |
| candidate | A | SSMT2024 | declared | height | 2 | 2 | 2 | 1.8 | 0.2 |
| candidate | A | SSMT2024 | declared | rank | 2 | 2 | 2 | 2.6 | 0.7 |
| candidate | B | MNPK2018 | amendment1 | rank | 6 | 6 | 5 | 5.2 | 0.3 |
| candidate | B | MNPK2018 | declared | rank | 6 | 6 | 3 | 6.0 | 2.1 |
| candidate | B | STEF2018 | amendment1 | rank | 7 | 7 | 7 | 0.1 | 0.2 |
| candidate | B | STEF2018 | declared | rank | 7 | 7 | 5 | 1.6 | 1.5 |
| candidate | C | Eshom2020 | amendment1 | height | 33 | 11 | 0 | — | 11.6 |
| candidate | C | Eshom2020 | amendment1 | rank | 32 | 10 | 1 | 6.8 | 10.7 |
| candidate | C | Eshom2020 | declared | height | 33 | 0 | 0 | — | — |
| candidate | C | Eshom2020 | declared | rank | 32 | 0 | 0 | — | — |
| candidate | C | FOCAL2022 | amendment1 | height | 4 | 4 | 4 | 3.0 | 1.1 |
| candidate | C | FOCAL2022 | amendment1 | rank | 4 | 4 | 4 | 2.9 | 1.0 |
| candidate | C | FOCAL2022 | declared | height | 4 | 4 | 2 | 0.0 | 1.3 |
| candidate | C | FOCAL2022 | declared | rank | 4 | 4 | 0 | — | 3.4 |
| candidate | C | FOCAL2023 | amendment1 | height | 4 | 4 | 1 | 7.4 | 6.8 |
| candidate | C | FOCAL2023 | amendment1 | rank | 4 | 4 | 2 | 5.9 | 6.4 |
| candidate | C | FOCAL2023 | declared | height | 4 | 2 | 1 | 5.6 | 4.7 |
| candidate | C | FOCAL2023 | declared | rank | 4 | 2 | 0 | — | 8.7 |
| candidate | C | SSI2023 | amendment1 | height | 1 | 1 | 0 | — | 8.6 |
| candidate | C | SSI2023 | amendment1 | rank | 1 | 1 | 0 | — | 9.2 |
| candidate | C | SSI2023 | declared | height | 1 | 1 | 0 | — | 6.1 |
| candidate | C | SSI2023 | declared | rank | 1 | 1 | 0 | — | 10.9 |
| candidate | C | TNC2023 | amendment1 | height | 24 | 24 | 24 | 1.2 | 0.7 |
| candidate | C | TNC2023 | amendment1 | rank | 24 | 24 | 21 | 1.1 | 0.7 |
| candidate | C | TNC2023 | declared | height | 24 | 24 | 14 | 1.1 | 1.8 |
| candidate | C | TNC2023 | declared | rank | 24 | 24 | 5 | 1.1 | 4.4 |
| candidate | C | VP2022 | amendment1 | height | 51 | 51 | 48 | 1.8 | 0.4 |
| candidate | C | VP2022 | amendment1 | rank | 51 | 51 | 50 | 1.7 | 0.5 |
| candidate | C | VP2022 | declared | height | 51 | 51 | 25 | 1.1 | 2.0 |
| candidate | C | VP2022 | declared | rank | 51 | 51 | 12 | 2.8 | 3.0 |
| candidate | D | CRBLDG2022 | amendment1 | rank | 4 | 4 | 4 | 2.1 | 0.4 |
| candidate | D | CRBLDG2022 | declared | rank | 4 | 4 | 1 | 1.6 | 2.1 |
| candidate | all | all projects | amendment1 | height | 123 | 101 | 83 | 1.7 | 0.6 |
| candidate | all | all projects | amendment1 | rank | 139 | 117 | 98 | 1.7 | 0.6 |
| candidate | all | all projects | declared | height | 123 | 88 | 45 | 1.1 | 2.0 |
| candidate | all | all projects | declared | rank | 139 | 105 | 29 | 2.1 | 2.8 |
| heldout | B | DS2024 | amendment1 | rank | 3 | 3 | 3 | 1.5 | 0.1 |
| heldout | B | DS2024 | declared | rank | 3 | 3 | 3 | 2.1 | 0.7 |
| heldout | B | OHDS2024 | amendment1 | rank | 1 | 1 | 1 | 3.8 | 8.4 |
| heldout | B | OHDS2024 | declared | rank | 1 | 1 | 0 | — | 8.1 |
| heldout | B | SJGEO2018 | amendment1 | rank | 1 | 1 | 1 | 1.4 | 0.6 |
| heldout | B | SJGEO2018 | declared | rank | 1 | 1 | 1 | 1.6 | 1.5 |
| heldout | B | STEF2007 | amendment1 | rank | 4 | 4 | 4 | 1.4 | 0.2 |
| heldout | B | STEF2007 | declared | rank | 4 | 4 | 3 | 1.1 | 1.0 |
| heldout | B | STEF2018 | amendment1 | rank | 1 | 1 | 1 | 4.0 | 0.5 |
| heldout | B | STEF2018 | declared | rank | 1 | 1 | 1 | 4.0 | 1.9 |
| heldout | — | Cambria2021 | amendment1 | rank | 21 | 14 | 5 | 4.7 | 9.7 |
| heldout | — | Cambria2021 | declared | rank | 21 | 11 | 0 | — | 13.2 |
| heldout | — | FOCAL2020 | amendment1 | height | 10 | 10 | 10 | 1.7 | 0.3 |
| heldout | — | FOCAL2020 | declared | height | 10 | 10 | 7 | 2.1 | 1.6 |
| heldout | — | FOCAL2025 | amendment1 | height | 4 | 4 | 4 | 5.4 | 1.3 |
| heldout | — | FOCAL2025 | amendment1 | rank | 4 | 4 | 3 | 4.8 | 1.1 |
| heldout | — | FOCAL2025 | declared | height | 4 | 4 | 2 | 3.7 | 2.2 |
| heldout | — | FOCAL2025 | declared | rank | 4 | 4 | 1 | 3.5 | 2.9 |
| heldout | — | WADNR2023 | amendment1 | rank | 11 | 11 | 8 | 3.7 | 1.3 |
| heldout | — | WADNR2023 | declared | rank | 11 | 9 | 3 | 4.5 | 4.7 |
| heldout | all | all projects | amendment1 | height | 14 | 14 | 14 | 2.6 | 0.4 |
| heldout | all | all projects | amendment1 | rank | 46 | 39 | 26 | 3.5 | 1.4 |
| heldout | all | all projects | declared | height | 14 | 14 | 9 | 2.1 | 1.6 |
| heldout | all | all projects | declared | rank | 46 | 34 | 12 | 2.1 | 4.4 |

Rows of method `declared` are the first method, kept for the record. The
shift, residual and acceptance of each held-out plot are in the
[second appendix](#appendix-held-out-catalogue-plots).
Under the frozen method the gate accepts 83 of 101 candidate plots on the
height signal and 98 of 117 on the diameter signal, with a median shift of
1.7 m. Shifts are near zero at `STEF2018` and about 5 to 7 m on three
`MNPK2018` plots.

| Record | Plots with both signals accepted | Within 2 m | Result |
| --- | --- | --- | --- |
| declared | 14 | 11 (78.6%) | fail |
| declared | Pass rule: at least 10 | at least 80.0% | — |
| amendment1.catalog | 81 | 80 (98.8%) | pass |

Under the frozen method the two signals agree within 2 m on 80 of 81
plots. That shows they are consistent, not that they are right. Under the
declared method they agree on 11 of 14, below the 80% the protocol asks.
Before the second amendment and the corrections listed in the protocol that
count was 15 of 18, a pass: four plots left the set when withheld returns
were dropped and the polygons were stored in full precision.

| Plot | Project | Group | Signal | Method | Stems | dx, m | dy, m | Shift, m | Residual, m | Contrast | Accepted | Registered | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0068 | EP2018 | A | height | amendment1 | 1,841 | 1.8 | -1.1 | 2.1 | 0.1 | 0.58 | yes | no | signal_not_admitted |
| 0084 | JLHZ2019 | A | height | amendment1 | 725 | -0.7 | -0.7 | 1.0 | 1.6 | 0.24 | yes | no | signal_not_admitted |
| 0085 | JLHZ2019 | A | height | amendment1 | 1,375 | 0.4 | -2.2 | 2.2 | 1.1 | 0.21 | yes | no | signal_not_admitted |
| 0086 | JLHZ2019 | A | height | amendment1 | 1,577 | 1.6 | >-0.1 | 1.6 | 1.3 | 0.26 | yes | no | signal_not_admitted |
| 0282 | SSMT2024 | A | height | amendment1 | 936 | 2.5 | -0.2 | 2.5 | 0.1 | 0.38 | yes | no | signal_not_admitted |
| 0283 | SSMT2024 | A | height | amendment1 | 935 | 0.8 | -2.4 | 2.5 | <0.1 | 0.48 | yes | no | signal_not_admitted |
| 0073 | STEF2018 | B | rank | amendment1 | 309 | <0.1 | 0.1 | 0.1 | 0.2 | 0.30 | yes | no | signal_not_admitted |
| 0074 | STEF2018 | B | rank | amendment1 | 416 | -0.1 | -0.1 | 0.1 | 0.2 | 0.34 | yes | no | signal_not_admitted |
| 0075 | STEF2018 | B | rank | amendment1 | 499 | -0.1 | <0.1 | 0.1 | 0.1 | 0.37 | yes | no | signal_not_admitted |
| 0076 | STEF2018 | B | rank | amendment1 | 338 | -0.1 | 0.1 | 0.2 | 0.2 | 0.35 | yes | no | signal_not_admitted |
| 0077 | STEF2018 | B | rank | amendment1 | 319 | -0.1 | -0.1 | 0.1 | 0.1 | 0.37 | yes | no | signal_not_admitted |
| 0078 | STEF2018 | B | rank | amendment1 | 302 | -0.1 | >-0.1 | 0.1 | 0.2 | 0.35 | yes | no | signal_not_admitted |
| 0080 | STEF2018 | B | rank | amendment1 | 377 | >-0.1 | 0.1 | 0.1 | 0.2 | 0.30 | yes | no | signal_not_admitted |
| 0197 | MNPK2018 | B | rank | amendment1 | 109 | -1.0 | -5.1 | 5.2 | 0.2 | 0.35 | yes | no | signal_not_admitted |
| 0198 | MNPK2018 | B | rank | amendment1 | 117 | 1.4 | -1.2 | 1.8 | 0.7 | 0.33 | yes | no | signal_not_admitted |
| 0199 | MNPK2018 | B | rank | amendment1 | 129 | 6.1 | 2.8 | 6.7 | 0.2 | 0.35 | yes | no | signal_not_admitted |
| 0200 | MNPK2018 | B | rank | amendment1 | 59 | -12.0 | -5.1 | 13.0 | 1.7 | 0.28 | no | no | signal_not_admitted;on_edge |
| 0201 | MNPK2018 | B | rank | amendment1 | 138 | -5.9 | -0.8 | 5.9 | 0.3 | 0.36 | yes | no | signal_not_admitted |
| 0202 | MNPK2018 | B | rank | amendment1 | 100 | 0.7 | -1.8 | 1.9 | 0.2 | 0.33 | yes | no | signal_not_admitted |
| 0115 | CRBLDG2022 | D | rank | amendment1 | 415 | -1.6 | -1.7 | 2.4 | 0.4 | 0.26 | yes | no | signal_not_admitted |
| 0116 | CRBLDG2022 | D | rank | amendment1 | 264 | 2.2 | 0.9 | 2.4 | 0.4 | 0.29 | yes | no | signal_not_admitted |
| 0117 | CRBLDG2022 | D | rank | amendment1 | 97 | -0.6 | 1.6 | 1.7 | 0.7 | 0.23 | yes | no | signal_not_admitted |
| 0118 | CRBLDG2022 | D | rank | amendment1 | 187 | -0.8 | 0.9 | 1.2 | 0.4 | 0.29 | yes | no | signal_not_admitted |
| 0204 | Eshom2020 | D | rank | amendment1 | — | — | — | — | — | — | — | no | signal_not_admitted;not_run |
| 0212 | Eshom2020 | D | rank | amendment1 | — | — | — | — | — | — | — | no | signal_not_admitted;not_run |
| 0228 | Eshom2020 | D | rank | amendment1 | — | — | — | — | — | — | — | no | signal_not_admitted;not_run |
| 0231 | Eshom2020 | D | rank | amendment1 | — | — | — | — | — | — | — | no | signal_not_admitted;not_run |
| 0235 | Eshom2020 | D | rank | amendment1 | — | — | — | — | — | — | — | no | signal_not_admitted;not_run |
| 0236 | Eshom2020 | D | rank | amendment1 | — | — | — | — | — | — | — | no | signal_not_admitted;not_run |

## Disturbance, snow and leaf-off

| Group | Project | Plots with a cloud | Undisturbed | Disturbed | Unresolved | Disturbance not checked | Not winter | Snow-free | Snow | Snow unknown | Leaf-on | Leaf-off minor | Leaf-off held | Conditions admitted |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A | EP2018 | 1 | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 1 |
| A | JLHZ2019 | 3 | 2 | 1 | 0 | 0 | 1 | 2 | 0 | 0 | 1 | 0 | 2 | 0 |
| A | SSMT2024 | 2 | 2 | 0 | 0 | 0 | 2 | 0 | 0 | 0 | 2 | 0 | 0 | 1 |
| A | all projects | 6 | 5 | 1 | 0 | 0 | 4 | 2 | 0 | 0 | 4 | 0 | 2 | 2 |
| B | DS2024 | 3 | 0 | 0 | 0 | 3 | 0 | 3 | 0 | 0 | 0 | 3 | 0 | 0 |
| B | MNPK2018 | 6 | 1 | 2 | 3 | 0 | 6 | 0 | 0 | 0 | 6 | 0 | 0 | 0 |
| B | OHDS2024 | 1 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 1 | 0 | 1 |
| B | SJGEO2018 | 1 | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 1 |
| B | STEF2007 | 4 | 4 | 0 | 0 | 0 | 2 | 2 | 0 | 0 | 2 | 2 | 0 | 0 |
| B | STEF2018 | 8 | 6 | 2 | 0 | 0 | 7 | 1 | 0 | 0 | 7 | 1 | 0 | 0 |
| B | all projects | 23 | 13 | 4 | 3 | 3 | 16 | 7 | 0 | 0 | 16 | 7 | 0 | 2 |
| C | Eshom2020 | 33 | 7 | 18 | 8 | 0 | 33 | 0 | 0 | 0 | 33 | 0 | 0 | 6 |
| C | FOCAL2022 | 4 | 4 | 0 | 0 | 0 | 0 | 4 | 0 | 0 | 0 | 4 | 0 | 4 |
| C | FOCAL2023 | 4 | 0 | 3 | 1 | 0 | 0 | 4 | 0 | 0 | 0 | 4 | 0 | 0 |
| C | SSI2023 | 1 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 1 | 0 |
| C | TNC2023 | 24 | 17 | 3 | 1 | 3 | 2 | 20 | 2 | 0 | 2 | 19 | 3 | 15 |
| C | VP2022 | 51 | 36 | 5 | 1 | 9 | 25 | 26 | 0 | 0 | 25 | 25 | 1 | 38 |
| C | all projects | 117 | 65 | 29 | 11 | 12 | 60 | 55 | 2 | 0 | 60 | 52 | 5 | 63 |
| D | CRBLDG2022 | 4 | 4 | 0 | 0 | 0 | 0 | 4 | 0 | 0 | 0 | 4 | 0 | 4 |
| D | Eshom2020 | 6 | 0 | 6 | 0 | 0 | 6 | 0 | 0 | 0 | 6 | 0 | 0 | 0 |
| D | all projects | 10 | 4 | 6 | 0 | 0 | 6 | 4 | 0 | 0 | 6 | 4 | 0 | 4 |
| — | Cambria2021 | 28 | 10 | 11 | 6 | 1 | 0 | 28 | 0 | 0 | 0 | 28 | 0 | 10 |
| — | FOCAL2020 | 10 | 3 | 3 | 4 | 0 | 6 | 4 | 0 | 0 | 3 | 7 | 0 | 3 |
| — | FOCAL2025 | 4 | 0 | 0 | 0 | 4 | 0 | 4 | 0 | 0 | 0 | 4 | 0 | 0 |
| — | WADNR2023 | 11 | 3 | 4 | 3 | 1 | 11 | 0 | 0 | 0 | 11 | 0 | 0 | 3 |
| — | all projects | 53 | 16 | 18 | 13 | 6 | 17 | 36 | 0 | 0 | 14 | 39 | 0 | 16 |

- **Disturbance.** 188 of the 209 plots with a cloud had a usable drone
  canopy model: 103 undisturbed, 58 disturbed and 27 unresolved. In most
  comparisons the 3DEP flight is the earlier surface, so "loss" means a
  photogrammetric canopy model below half the LiDAR height. Missed tree
  tops would look the same as lost trees. The check is therefore
  conservative: it holds plots it cannot clear, and part of what it holds
  may be disagreement between the two kinds of surface. It was not
  validated on plots of known history.

| Set | Plots checked | 3DEP flight earlier | Drone mission earlier | Mission year minus survey year | Mission year minus flight year |
| --- | --- | --- | --- | --- | --- |
| All checked plots | 188 | 174 | 14 | -1–16 | 1–11 |
| Groups A and B with an admitted flight | 19 | 18 | 1 | 3–6 | 1–3 |

- **Groups A and B.** For 18 of their 19 plots with an admitted flight the
  drone mission was flown after the 3DEP flight: three to six calendar
  years after the survey and one to three after the flight. Such a
  comparison covers the wrong interval. Only `EP2018` has a mission on the
  survey side, and `SSMT2024` plot 0283 passes because flight and survey
  share a year. No earlier public 3DEP flight exists for most of these
  plots, so the declared sources cannot clear them.
- **Snow.** 106 plots were flown between November and April. SNODAS gives
  zero depth on every flight day for 104. Two `TNC2023` plots are held at
  modelled depths of 2 and 4 mm; the protocol has no tolerance.
- **Leaf-off.** Seven plots are held because winter-deciduous species make
  up 10% or more of their reference stems and the flight was leaf-off.

| Plot | Project | Group | Flight admitted | Survey date | Flight date | Mission date | Interval covered | Disturbance | Loss share | Reverse share | Snow | Snow depth, mm (max) | Leaf-off | Deciduous share | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0084 | JLHZ2019 | A | yes | 2019-07-15 | 2022-06-10 | 2023-06-08 | no | disturbed | 31.9% | 1.7% | not_winter | — | leaf_on | 8.7% | disturbed |
| 0085 | JLHZ2019 | A | yes | 2020-06-15 | 2022-10-15 | 2023-07-31 | no | undisturbed | 1.4% | 1.7% | snow_free | 0 | leaf_off_held | 11.4% | interval_not_covered;leaf_off |
| 0086 | JLHZ2019 | A | yes | 2020-06-15 | 2022-10-15 | 2023-07-30 | no | undisturbed | 0.1% | 0.6% | snow_free | 0 | leaf_off_held | 15.6% | interval_not_covered;leaf_off |
| 0282 | SSMT2024 | A | yes | 2021-07-01 | 2022-08-02 | 2024-08-07 | no | undisturbed | 0.0% | 0.0% | not_winter | — | leaf_on | 0.0% | interval_not_covered |
| 0069 | STEF2007 | B | no | 2016-07-01 | 2021-11-21 | 2023-07-24 | no | undisturbed | 2.1% | 0.4% | snow_free | 0 | leaf_off_minor | 0.1% | interval_not_covered |
| 0070 | STEF2007 | B | no | 2008-07-01 | 2022-06-14 | 2024-06-07 | no | undisturbed | 6.9% | 4.2% | not_winter | — | leaf_on | 0.0% | interval_not_covered |
| 0071 | STEF2007 | B | no | 2008-07-01 | 2022-06-14 | 2024-06-07 | no | undisturbed | 8.7% | 4.5% | not_winter | — | leaf_on | <0.1% | interval_not_covered |
| 0072 | STEF2007 | B | no | 2007-07-01 | 2021-11-21 | 2023-07-24 | no | undisturbed | 2.4% | 0.2% | snow_free | 0 | leaf_off_minor | 0.8% | interval_not_covered |
| 0073 | STEF2018 | B | yes | 2018-07-01 | 2022-06-14 | 2023-07-24 | no | undisturbed | 8.2% | 2.0% | not_winter | — | leaf_on | 1.3% | interval_not_covered |
| 0074 | STEF2018 | B | yes | 2018-07-01 | 2022-06-14 | 2023-07-24 | no | undisturbed | 3.9% | 1.0% | not_winter | — | leaf_on | 0.0% | interval_not_covered |
| 0075 | STEF2018 | B | yes | 2018-07-01 | 2022-06-14 | 2023-07-24 | no | undisturbed | 4.6% | 0.4% | not_winter | — | leaf_on | 0.6% | interval_not_covered |
| 0076 | STEF2018 | B | yes | 2018-07-01 | 2022-06-14 | 2023-07-24 | no | undisturbed | 3.3% | 0.9% | not_winter | — | leaf_on | 2.1% | interval_not_covered |
| 0077 | STEF2018 | B | yes | 2018-07-01 | 2022-06-14 | 2023-07-24 | no | disturbed | 14.3% | 7.7% | not_winter | — | leaf_on | 0.3% | disturbed |
| 0078 | STEF2018 | B | yes | 2018-07-01 | 2022-06-14 | 2023-07-24 | no | disturbed | 19.0% | 3.7% | not_winter | — | leaf_on | 0.3% | disturbed |
| 0079 | STEF2018 | B | no | 2018-07-01 | 2021-11-21 | 2023-07-24 | no | undisturbed | 9.8% | 3.0% | snow_free | 0 | leaf_off_minor | 1.2% | interval_not_covered |
| 0080 | STEF2018 | B | yes | 2018-07-01 | 2022-06-14 | 2023-07-24 | no | undisturbed | 7.9% | 2.8% | not_winter | — | leaf_on | 0.0% | interval_not_covered |
| 0197 | MNPK2018 | B | yes | 2018-08-14 | 2022-06-08 | 2024-06-09 | no | disturbed | 12.6% | 3.6% | not_winter | — | leaf_on | 0.0% | disturbed |
| 0198 | MNPK2018 | B | yes | 2018-08-16 | 2022-06-08 | 2024-06-09 | no | undisturbed | 8.6% | 1.7% | not_winter | — | leaf_on | 0.0% | interval_not_covered |
| 0199 | MNPK2018 | B | yes | 2018-08-23 | 2022-06-08 | 2024-06-09 | no | disturbed | 14.2% | 2.2% | not_winter | — | leaf_on | 0.0% | disturbed |
| 0200 | MNPK2018 | B | yes | 2018-08-21 | 2022-06-15 | 2024-06-11 | no | unresolved | 28.9% | 14.8% | not_winter | — | leaf_on | 0.0% | unresolved |
| 0201 | MNPK2018 | B | yes | 2018-08-28 | 2022-06-15 | 2024-06-11 | no | unresolved | 32.6% | 16.4% | not_winter | — | leaf_on | 0.0% | unresolved |
| 0202 | MNPK2018 | B | yes | 2018-08-29 | 2022-06-15 | 2024-06-11 | no | unresolved | 30.2% | 17.7% | not_winter | — | leaf_on | 0.0% | unresolved |
| 0287 | DS2024 | B | no | 2013-07-01 | 2021-03-31 | — | — | not_checked | — | — | snow_free | 0 | leaf_off_minor | 9.3% | no_usable_drone_model |
| 0288 | DS2024 | B | no | 2013-07-01 | 2021-03-31 | — | — | not_checked | — | — | snow_free | 0 | leaf_off_minor | 1.1% | no_usable_drone_model |
| 0290 | DS2024 | B | no | 2013-07-01 | 2021-03-31 | — | — | not_checked | — | — | snow_free | 0 | leaf_off_minor | 4.8% | no_usable_drone_model |
| 0204 | Eshom2020 | D | yes | 2022-09-10 | 2022-06-08 | 2023-08-17 | yes | disturbed | 44.4% | 0.0% | not_winter | — | leaf_on | — | disturbed |
| 0212 | Eshom2020 | D | yes | 2022-07-07 | 2022-06-08 | 2023-08-17 | yes | disturbed | 40.0% | 0.0% | not_winter | — | leaf_on | — | disturbed |
| 0228 | Eshom2020 | D | yes | 2022-07-11 | 2022-06-08 | 2023-08-18 | yes | disturbed | 100.0% | — | not_winter | — | leaf_on | — | disturbed |
| 0231 | Eshom2020 | D | yes | 2022-07-06 | 2022-06-08 | 2023-08-18 | yes | disturbed | 100.0% | — | not_winter | — | leaf_on | — | disturbed |
| 0235 | Eshom2020 | D | yes | 2022-07-14 | 2022-06-08 | 2023-08-18 | yes | disturbed | 76.9% | 0.0% | not_winter | — | leaf_on | — | disturbed |
| 0236 | Eshom2020 | D | yes | 2022-07-12 | 2022-06-08 | 2023-08-18 | yes | disturbed | 75.0% | 0.0% | not_winter | — | leaf_on | — | disturbed |

## Scoring cells and reference tables

No cell was computed and no reference table was written, because no plot
was registered. The tiling into 40 m cells and the mapping to the
`ground_truth_stems.csv` schema are implemented and unit-tested, including
a test that the benchmark's own unchanged readers and scorer accept the
tables. The table below shows what each gate costs, in order.

| Group | Step | Gate | Failing this gate, at any step | Removed at this step | Plots left |
| --- | --- | --- | --- | --- | --- |
| A | 0 | plots | — | — | 13 |
| A | 1 | screen_ok | 0 | 0 | 13 |
| A | 2 | flight_admitted | 7 | 7 | 6 |
| A | 3 | geometry_consistent | 0 | 0 | 6 |
| A | 4 | conditions_admitted | 11 | 4 | 2 |
| A | 5 | registered | 13 | 2 | 0 |
| A | — | admitted | — | — | 0 |
| B | 0 | plots | — | — | 32 |
| B | 1 | screen_ok | 0 | 0 | 32 |
| B | 2 | flight_admitted | 19 | 19 | 13 |
| B | 3 | geometry_consistent | 4 | 0 | 13 |
| B | 4 | conditions_admitted | 30 | 13 | 0 |
| B | 5 | registered | 32 | 0 | 0 |
| B | — | admitted | — | — | 0 |
| C | 0 | plots | — | — | 117 |
| C | 1 | screen_ok | 0 | 0 | 117 |
| C | 2 | flight_admitted | 0 | 0 | 117 |
| C | 3 | geometry_consistent | 4 | 4 | 113 |
| C | 4 | conditions_admitted | 54 | 50 | 63 |
| C | 5 | registered | 117 | 63 | 0 |
| C | — | admitted | — | — | 0 |
| D | 0 | plots | — | — | 10 |
| D | 1 | screen_ok | 0 | 0 | 10 |
| D | 2 | flight_admitted | 0 | 0 | 10 |
| D | 3 | geometry_consistent | 6 | 6 | 4 |
| D | 4 | conditions_admitted | 6 | 0 | 4 |
| D | 5 | registered | 10 | 4 | 0 |
| D | — | admitted | — | — | 0 |
| — | 0 | plots | — | — | 53 |
| — | 1 | screen_ok | 53 | 53 | 0 |
| — | 2 | flight_admitted | 30 | 0 | 0 |
| — | 3 | geometry_consistent | 28 | 0 | 0 |
| — | 4 | conditions_admitted | 37 | 0 | 0 |
| — | 5 | registered | 53 | 0 | 0 |
| — | — | admitted | — | — | 0 |
| all groups | 0 | plots | — | — | 172 |
| all groups | 1 | screen_ok | 0 | 0 | 172 |
| all groups | 2 | flight_admitted | 26 | 26 | 146 |
| all groups | 3 | geometry_consistent | 14 | 10 | 136 |
| all groups | 4 | conditions_admitted | 101 | 67 | 69 |
| all groups | 5 | registered | 172 | 69 | 0 |
| all groups | — | admitted | — | — | 0 |

Before registration, the conditions gate removes the most plots over all
groups: 67, against 26 for the flight gate and 10 for geometry. It also
removes the largest share of the plots that reach it: 4 of the 6
flight-admitted plots in group A, all 13 in B and 50 of the 113
geometry-consistent plots in C. In A and B the flight gate removes more
plots, 7 and 19, from larger sets. In D the conditions gate removes none,
because the geometry gate had already removed the six plots without live
stems.

The next table is indicative only. It applies the tiling rule to the
unshifted polygons of plots with an admitted flight, to show which plots
could hold a cell at all.

| Group | Project | Plots with an admitted flight | Plots that can hold a cell | Cells | Plot polygon area, m² (range) |
| --- | --- | --- | --- | --- | --- |
| A | EP2018 | 1 | 1 | 15 | 32,302 |
| A | JLHZ2019 | 3 | 3 | 30 | 20,083–39,974 |
| A | SSMT2024 | 2 | 2 | 8 | 11,809–12,316 |
| A | all projects | 6 | 6 | 53 | 11,809–39,974 |
| B | MNPK2018 | 6 | 6 | 24 | 9,959 |
| B | STEF2018 | 7 | 7 | 73 | 21,716–29,851 |
| B | all projects | 13 | 13 | 97 | 9,959–29,851 |
| C | Eshom2020 | 33 | 0 | 0 | 402 |
| C | FOCAL2022 | 4 | 2 | 2 | 1,597–3,593 |
| C | FOCAL2023 | 4 | 4 | 5 | 2,816–7,822 |
| C | SSI2023 | 1 | 1 | 1 | 2,907 |
| C | TNC2023 | 24 | 24 | 24 | 2,907 |
| C | VP2022 | 51 | 51 | 51 | 2,907 |
| C | all projects | 117 | 82 | 83 | 402–7,822 |
| D | CRBLDG2022 | 4 | 4 | 13 | 9,998 |
| D | Eshom2020 | 6 | 0 | 0 | 402 |
| D | all projects | 10 | 4 | 13 | 402–9,998 |

All 39 `Eshom2020` plots are circles of 402 m² and cannot hold a 40 m
cell, and neither can two `FOCAL2022` plots. So at most 82 of the 117 group
C plots and the four `CRBLDG2022` plots of group D could be scored under
this tiling, whatever the registration.

## Plots outside the public 3DEP clouds

Fourteen plots of `OHDS2024` and `SSMT2024` have no admitted flight:
thirteen lie outside every Entwine resource and plot 0270 has only a 2013
flight. Public collections cover each of them, found from footprints, tile
indexes and metadata only. Most are USGS work units of quality level 1 that
have downloadable tiles and no Entwine resource. No point cloud was
acquired; a plot gains a flight only through an amendment that names the
collection. The six `DS2024` plots, surveyed in 2013 and without an
admitted flight, were not searched.

| Plot | Project | Survey year | USGS tiles without an Entwine resource | Washington DNR | Oregon DOGAMI | NOAA Digital Coast | Other candidates |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0270 | OHDS2024 | 2019 | WA_Olympic_Peninsula_C1_2017 (2017, 2019) | Olympics South Opsw 2019 (2019) | — | 2017 USGS Lidar: Olympic Peninsula, WA (2017, 2018) | 4 |
| 0271 | OHDS2024 | 2019 | WA_Olympic_Peninsula_C3_2017 (2017, 2018) | Olympics North Opsw 2018 (2018); Solduc 2015 (2015) | — | 2015 PSLC Lidar: WA DNR Lands (P1) (2014, 2015); 2017 USGS Lidar: Olympic Peninsula, WA (2017, 2018) | 1 |
| 0272 | OHDS2024 | 2018 | WA_Olympic_Peninsula_C3_2017 (2017, 2018) | Olympics North Opsw 2018 (2018); Solduc 2015 (2015) | — | 2015 PSLC Lidar: WA DNR Lands (P1) (2014, 2015); 2017 USGS Lidar: Olympic Peninsula, WA (2017, 2018) | 1 |
| 0273 | OHDS2024 | 2019 | WA_Olympic_Peninsula_C1_2017 (2017, 2019) | Olympics South Opsw 2019 (2019) | — | 2017 USGS Lidar: Olympic Peninsula, WA (2017, 2018) | 2 |
| 0274 | OHDS2024 | 2018 | WA_Olympic_Peninsula_C3_2017 (2017, 2018) | Olympic Park 2014 (2014); Olympics North Opsw 2018 (2018); Solduc 2015 (2015) | — | 2015 PSLC Lidar: WA DNR Lands (P1) (2014, 2015); 2017 USGS Lidar: Olympic Peninsula, WA (2017, 2018) | 0 |
| 0275 | OHDS2024 | 2019 | — | Olympics 2017 (2017) | — | 2017 USDA Forest Service Lidar: Olympic National Forest, WA (2017) | 1 |
| 0276 | OHDS2024 | 2019 | WA_Olympic_Peninsula_C1_2017 (2017, 2019) | Olympics South Opsw 2019 (2019) | — | 2017 USGS Lidar: Olympic Peninsula, WA (2017, 2018) | 3 |
| 0277 | SSMT2024 | 2021 | WA_Western_South_2016 (2016, 2017) | Swwa Foothills 2017 (2017) | — | 2016 USGS Lidar: West Washington (2016, 2017) | 2 |
| 0278 | SSMT2024 | 2021 | — | Puyallup Watershed Wali 2022 (2022) | — | — | 4 |
| 0279 | SSMT2024 | 2021 | OR_Western_3_D23 (2023, 2024) | — | Western Oregon 3DEP (2024) | — | 2 |
| 0280 | SSMT2024 | 2021 | OR_SoCoast_1_2019 (2020) | — | South Coast (2020) | — | 3 |
| 0281 | SSMT2024 | 2021 | WA_6County_2_A24 (2024, 2025) | Pacific County Refresh24 2025 (2025) | — | — | 2 |
| 0284 | SSMT2024 | 2021 | — | — | Western Oregon 3DEP (2024); Willamette Middle Fork and Breitenbush (2020) | 2020 USFS Lidar: Middle Fork, North and South Clackamas (OR, WA) (2020) | 0 |
| 0285 | SSMT2024 | 2021 | OR_2022Jackson_1_C25 (2022, 2023) | — | Jackson County 2022 (2022, 2023) | 2022 - 2023 DOGAMI/OLC Lidar: Jackson County, OR (2022, 2023) | 3 |

The full list, with access routes and terms, is in `state_lidar.csv`. Of
its 71 rows, 68 are verified against a footprint or tile index and three
are leads. `OHDS2024` would still fail on its rounded positions.

## Licences

Licences and contributors are the same for every plot of a project. The
plot-level list is the appendix below.

| Project | Plots | Licence | Contributors | Required citation | Withheld from training | Reference tables redistributable |
| --- | --- | --- | --- | --- | --- | --- |
| CRBLDG2022 | 4 | CC BY 4.0 | Connie P. Ryan, Robert A. York, Brandon M. Collins, Ariel T. Roughton, Scott L. Stephens | — | 1 | yes |
| Cambria2021 | 28 | CC BY 4.0 | Dr. Sarah Bisbing, Conor Phelan | — | 0 | yes |
| DS2024 | 6 | CC BY 4.0 | Dr. Constance Harrington &  David Marshall (Pacific Northwest Research Station, U.S. Forest Service), Dr. Derek Young (UC Davis) | — | 1 | yes |
| EP2018 | 1 | CC BY 4.0 | JonahMaria Weeks, Dr. Derek Young, Dr. Hugh Safford | — | 1 | yes |
| Eshom2020 | 39 | CC BY 4.0 | Dr. Sarah Bisbing, Bryant Nagelson | — | 24 | yes |
| FOCAL2020 | 10 | CC BY SA 4.0 | Dr. Derek Young | — | 2 | no |
| FOCAL2022 | 4 | CC BY SA 4.0 | Dr. Derek Young | — | 2 | no |
| FOCAL2023 | 4 | CC BY SA 4.0 | Dr. Derek Young | — | 0 | no |
| FOCAL2025 | 4 | CC BY SA 4.0 | Dr. Derek Young | — | 0 | no |
| JLHZ2019 | 3 | CC BY 4.0 | James Lamping, Harold Zald | — | 0 | yes |
| MNPK2018 | 6 | CC BY 4.0 | Dr. Malcolm North, Max Odland, Dr. Paige Kouba | — | 0 | yes |
| NEON2023 | 62 | CC0 1.0 | National Ecological Observatory Network (NEON) | — | 0 | yes |
| OHDS2024 | 7 | CC BY 4.0 | Dr. Constance Harrington (Pacific Northwest Research Station, U.S. Forest Service), Dr. Derek Young (UC Davis) | — | 2 | yes |
| SJGEO2018 | 1 | CC BY 4.0 | Dr. Marko Spasojevic | Spasojevic, Marko et al. (2023). Data from: Integrating ontogeny and ontogenetic dependency into community assembly [Dataset]. Dryad. <https://doi.org/10.6086/D1267D> | 0 | yes |
| SSI2023 | 1 | CC BY 4.0 | Sierra Streams Institute; Erin Andrew | — | 0 | yes |
| SSMT2024 | 9 | CC BY 4.0 | Dr. Constance Harrington (Pacific Northwest Research Station, U.S. Forest Service), Dr. Derek Young (UC Davis) | — | 2 | yes |
| STEF2007 | 4 | Public domain | Knapp, Eric E.; Carlson, Robert L | Knapp, Eric E.; Carlson, Robert L. 2021. Stanislaus-Tuolumne Experimental Forest ‘Methods of Cutting’ study plots 8-11: 88+ years of forest composition. Fort Collins, CO: Forest Service Research Data Archive. <https://doi.org/10.2737/RDS-2021-0061> | 0 | yes |
| STEF2018 | 8 | Public domain | Alexis Bernal | Bernal, Alexis B.; Kane, Jeffrey M.; Knapp, Eric E.; Zald, Harold. 2020. Inventory and boundaries of stands treated with variable density thinning within Stanislaus-Tuolumne Experimental Forest. Fort Collins, CO: Forest Service Research Data Archive. | 0 | yes |
| TNC2023 | 24 | CC BY SA 4.0 | Dr. Derek Young (UC Davis), Ed Smith (TNC) | — | 5 | no |
| VP2022 | 51 | CC BY NC SA 4.0 | Vibrant Planet, PBC | Acknowledge Vibrant Planet, PBC | 14 | no |
| WADNR2023 | 11 | CC BY 4.0 | Derek Churchhill | — | 2 | yes |
| All non-NEON projects | 225 | CC BY 4.0 (116), CC BY NC SA 4.0 (51), CC BY SA 4.0 (46), Public domain (12) | — | — | 56 | 128 of 225 plots |
| Whole catalogue | 287 | CC BY 4.0 (116), CC BY NC SA 4.0 (51), CC BY SA 4.0 (46), CC0 1.0 (62), Public domain (12) | — | — | 56 | 190 of 287 plots |

Reference tables could be redistributed for 128 of the 225 plots. For the
share-alike and non-commercial projects an archive could hold only shifts,
cells and tree identifiers. Nothing from these plots enters the benchmark's
archive at present.

## Limits

- The known-truth test assumes that NEON stems and NEON clouds agree. The
  Abby Road units, `SOAP_031` and `TEAK_046` suggest that this does not hold
  everywhere.
- Confirmation units are not independent: each composite contains plots
  that are also units.
- Test offsets of up to 8 m put the truth off-centre in the search window,
  unlike catalogue plots, whose estimated shifts are mostly below 3 m.
- The catalogue bounds plot positions only against its drone missions, not
  against the 3DEP clouds. Under the frozen method nine catalogue plots
  were estimated at the edge of the ±12 m window: `MNPK2018` 0200 in group
  B, four in group C (`VP2022` 0002, `FOCAL2023` 0113, `Eshom2020` 0208 and
  0232) and four held-out `Cambria2021` plots (0258, 0259, 0267 and 0268).
  The declared method put four more group C plots there (`VP2022` 0017 and
  0049, `SSI2023` 0052 and `TNC2023` 0097). Their shifts may exceed the
  window.
- The disturbance check was not validated against plots of known history.
- Survey dates are approximate for 286 of 287 plots, so time gaps are whole
  years.
- The datum difference of 1 to 1.5 m between WGS 84 and NAD83(2011) was
  left to the registration and is unresolved.

## Reproduce

```sh
export CLAUDE_JOB_DIR=$(pwd)/work
Rscript scripts/preflight_ofo_catalog.R CORES=8
Rscript scripts/preflight_ofo_registration.R STAGE=neon CORES=8
Rscript scripts/preflight_ofo_registration.R STAGE=dev CORES=8
Rscript scripts/preflight_ofo_registration.R STAGE=confirm CONFIRM=YES
Rscript scripts/preflight_ofo_registration.R STAGE=catalog CORES=8
Rscript scripts/preflight_ofo_conditions.R CORES=8
Rscript scripts/preflight_ofo_state_lidar.R
Rscript scripts/preflight_ofo_decision.R
Rscript scripts/report_ofo_preflight.R
```

The registration stages read the sealed NEON root and the five NEON
reference tables and write nothing there. Their SHA-256 digests and the
listing of the 3,097 files of the root were identical before and after
this study. The confirmation stage refuses to run a second time.

## Appendix: every non-NEON plot

| Plot | Project | Contributor plot ID | Group or screen | Survey year | Area, ha | Work unit | QL | Flight date(s) | Gap, years | All returns per m² | First returns per m² | Licence | Shift, m | Residual, m | Admitted | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0001 | VP2022 | 1-A-145 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 1 | 34.7 | 14.6 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0002 | VP2022 | 1-A-147 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 1 | 33.3 | 14.8 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted;on_edge;sub_p90_m) |
| 0003 | VP2022 | 1-A-150 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 | 1 | 46.5 | 19.0 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0004 | VP2022 | 10-A-114 | C | 2022 | 0.29 | CA_SierraNevada_5_2022 | QL 1 | 2022-06-29 | 0 | 23.0 | 12.8 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0005 | VP2022 | 10-A-115 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-30 | 0 | 41.0 | 24.4 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0006 | VP2022 | 10-A-127 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-30 | 0 | 27.5 | 16.8 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0007 | VP2022 | 11-A-104 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-30 | 0 | 39.1 | 19.5 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0008 | VP2022 | 11-A-107 | C | 2022 | 0.29 | CA_SierraNevada_5_2022 | QL 1 | 2022-06-29 | 0 | 37.9 | 21.2 | CC BY NC SA 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted) |
| 0009 | VP2022 | 11-A-109 | C | 2022 | 0.29 | CA_SierraNevada_5_2022 | QL 1 | 2022-06-29 | 0 | 37.3 | 21.7 | CC BY NC SA 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted) |
| 0010 | VP2022 | 15-A-129 | C | 2022 | 0.29 | CA_SierraNevada_5_2022 | QL 1 | 2022-06-29 | 0 | 38.5 | 18.8 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0011 | VP2022 | 15-A-135 | C | 2022 | 0.29 | CA_SierraNevada_5_2022 | QL 1 | 2022-06-29 | 0 | 29.4 | 13.6 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0012 | VP2022 | 15-A-143 | C | 2022 | 0.29 | CA_SierraNevada_5_2022 | QL 1 | 2022-08-20 | 0 | 31.6 | 18.8 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0013 | VP2022 | 18-A-56 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-16 to 2022-07-07 | 0 | 27.7 | 15.4 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0014 | VP2022 | 18-A-57 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-02 to 2022-06-21 | 0 | 21.7 | 11.9 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0015 | VP2022 | 18-A-62 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-02 to 2022-06-21 | 0 | 27.6 | 14.3 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0016 | VP2022 | 19-A-35 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-02 | 0 | 21.0 | 11.9 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0017 | VP2022 | 19-A-37 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-02 to 2022-06-21 | 0 | 24.9 | 15.3 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0018 | VP2022 | 19-A-43 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-02 | 0 | 28.5 | 17.8 | CC BY NC SA 4.0 | — | — | no | geometry_consistent; conditions_admitted (disturbed); registered (signal_not_admitted;sub_p90_m) |
| 0019 | VP2022 | 19-A-48 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-16 to 2022-07-07 | 0 | 24.5 | 16.6 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0020 | VP2022 | 19-A-50 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-02 | 0 | 24.9 | 13.9 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0021 | VP2022 | 2-A-151 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 1 | 45.8 | 19.9 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0022 | VP2022 | 2-A-152 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 1 | 31.3 | 15.0 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0023 | VP2022 | 2-A-157 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 to 2021-11-08 | 1 | 46.6 | 19.0 | CC BY NC SA 4.0 | — | — | no | conditions_admitted (no_usable_drone_model); registered (signal_not_admitted) |
| 0024 | VP2022 | 26-A-74 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-30 | 0 | 33.7 | 18.6 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0025 | VP2022 | 26-A-71 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-29 | 0 | 33.7 | 18.9 | CC BY NC SA 4.0 | — | — | no | conditions_admitted (unresolved); registered (signal_not_admitted) |
| 0026 | VP2022 | 26-A-72 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-29 | 0 | 27.9 | 17.2 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0027 | VP2022 | 26-A-87 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-30 | 0 | 37.1 | 21.0 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0028 | VP2022 | 26-B-73 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-30 | 0 | 36.9 | 18.0 | CC BY NC SA 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted) |
| 0029 | VP2022 | 3-A-166 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 to 2021-11-05 | 1 | 37.9 | 16.3 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0030 | VP2022 | 3-A-169 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 1 | 30.5 | 14.8 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0031 | VP2022 | 3-A-170 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 1 | 39.7 | 16.5 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0032 | VP2022 | 3-A-182 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 to 2021-11-08 | 1 | 28.7 | 13.1 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0033 | VP2022 | 3-A-305 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 to 2021-11-05 | 1 | 50.1 | 20.1 | CC BY NC SA 4.0 | — | — | no | conditions_admitted (no_usable_drone_model); registered (signal_not_admitted) |
| 0034 | VP2022 | 3-B-167 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 to 2021-11-05 | 1 | 46.0 | 22.5 | CC BY NC SA 4.0 | — | — | no | conditions_admitted (no_usable_drone_model); registered (signal_not_admitted) |
| 0035 | VP2022 | 4-A-180 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-08 | 1 | 30.4 | 15.0 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0036 | VP2022 | 4-A-194 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 to 2021-11-05 | 1 | 30.3 | 13.0 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted;sub_p90_m) |
| 0037 | VP2022 | 4-A-195 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 to 2021-11-08 | 1 | 41.0 | 19.1 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0038 | VP2022 | 6-A-208 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-29 | 0 | 32.8 | 18.0 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0039 | VP2022 | 6-A-181 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 1 | 37.4 | 16.2 | CC BY NC SA 4.0 | — | — | no | conditions_admitted (no_usable_drone_model); registered (signal_not_admitted) |
| 0040 | VP2022 | 6-A-184 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-08 | 1 | 29.9 | 15.0 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0041 | VP2022 | 6-A-189 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 1 | 33.1 | 16.5 | CC BY NC SA 4.0 | — | — | no | conditions_admitted (no_usable_drone_model); registered (signal_not_admitted) |
| 0042 | VP2022 | 6-A-198 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 to 2021-11-05 | 1 | 35.6 | 16.4 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0043 | VP2022 | 6-A-203 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 to 2021-11-05 | 1 | 34.4 | 15.5 | CC BY NC SA 4.0 | — | — | no | conditions_admitted (no_usable_drone_model;leaf_off); registered (signal_not_admitted) |
| 0044 | VP2022 | 6-A-207 | C | 2022 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-06-29 to 2022-08-19 | 0 | 34.3 | 18.0 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0045 | VP2022 | 7-A-304 | C | 2022 | 0.29 | CA_NoCAL_Wildfires_PlumasNF_B2_2018 | QL 1 | 2018-08-17 | 4 | 14.2 | 10.2 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0046 | VP2022 | 7-A-94 | C | 2022 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 to 2021-11-08 | 1 | 32.8 | 16.8 | CC BY NC SA 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted) |
| 0047 | VP2022 | 7-A-96 | C | 2022 | 0.29 | CA_SierraNevada_1_2022 | QL 1 | 2021-11-23 | 1 | 36.9 | 18.4 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0048 | VP2022 | 7-D-97 | C | 2022 | 0.29 | CA_SierraNevada_1_2022 | QL 1 | 2021-11-23 | 1 | 32.8 | 18.0 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0049 | VP2022 | 8-A-301 | C | 2022 | 0.29 | CA_SierraNevada_1_2022 | QL 1 | 2021-11-23 | 1 | 34.2 | 17.4 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0050 | VP2022 | 8-A-302 | C | 2022 | 0.29 | CA_SierraNevada_1_2022 | QL 1 | 2021-11-23 | 1 | 30.2 | 13.2 | CC BY NC SA 4.0 | — | — | no | conditions_admitted (no_usable_drone_model); registered (signal_not_admitted) |
| 0051 | VP2022 | 8-B-303 | C | 2022 | 0.29 | CA_SierraNevada_1_2022 | QL 1 | 2021-11-23 | 1 | 29.3 | 14.9 | CC BY NC SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0052 | SSI2023 | 1 | C | 2023 | 0.29 | CA_SierraNevada_2_2022 | QL 1 | 2021-11-25 | 2 | 36.4 | 12.9 | CC BY 4.0 | — | — | no | conditions_admitted (leaf_off); registered (signal_not_admitted;sub_p90_m) |
| 0058 | FOCAL2020 | Chips_1 | no_diameter_floor | 2020 | 1.46 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-25 | 1 | 43.9 | 23.6 | CC BY SA 4.0 | — | — | no | screen_ok (no_diameter_floor); geometry_consistent; registered |
| 0059 | FOCAL2020 | Valley_1 | no_diameter_floor | 2020 | 0.95 | CA_NorthCoastRanges_2_B23 | QL 1 | 2023-09-20 to 2023-11-20 | 3 | 25.4 | 14.9 | CC BY SA 4.0 | — | — | no | screen_ok (no_diameter_floor); geometry_consistent; conditions_admitted (unresolved); registered |
| 0060 | FOCAL2020 | Lassic_1 | no_diameter_floor | 2020 | 1.31 | CA_NoCAL_Wildfires_B4_2018 | QL 2 | 2019-04-28 to 2019-08-09 | 1 | 7.1 | 4.8 | CC BY SA 4.0 | — | — | no | screen_ok (no_diameter_floor); flight_admitted (quality_level); geometry_consistent; conditions_admitted (unresolved); registered |
| 0061 | FOCAL2020 | Delta_1 | no_diameter_floor | 2020 | 1.29 | CA_CarrHirzDeltaFires_1_2019 | QL 1 | 2019-10-25 | 1 | 30.7 | 17.6 | CC BY SA 4.0 | — | — | no | screen_ok (no_diameter_floor); geometry_consistent; conditions_admitted (disturbed); registered |
| 0062 | FOCAL2020 | Lassic_2 | no_diameter_floor | 2021 | 1.40 | CA_NoCAL_Wildfires_B4_2018 | QL 2 | 2019-08-09 | 2 | 9.7 | 5.2 | CC BY SA 4.0 | — | — | no | screen_ok (no_diameter_floor); flight_admitted (quality_level); geometry_consistent; conditions_admitted (unresolved); registered |
| 0063 | FOCAL2020 | Delta_2 | no_diameter_floor | 2020 | 1.46 | CA_CarrHirzDeltaFires_1_2019 | QL 1 | 2019-10-25 | 1 | 39.6 | 21.4 | CC BY SA 4.0 | — | — | no | screen_ok (no_diameter_floor); geometry_consistent; conditions_admitted (disturbed); registered |
| 0064 | FOCAL2020 | Chips_2 | no_diameter_floor | 2020 | 0.42 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-25 | 1 | 25.8 | 17.9 | CC BY SA 4.0 | — | — | no | screen_ok (no_diameter_floor); geometry_consistent; registered |
| 0065 | FOCAL2020 | Delta_3 | no_diameter_floor | 2021 | 0.48 | CA_CarrHirzDeltaFires_1_2019 | QL 1 | 2019-10-25 | 2 | 37.7 | 18.9 | CC BY SA 4.0 | — | — | no | screen_ok (no_diameter_floor); geometry_consistent; conditions_admitted (disturbed); registered |
| 0066 | FOCAL2020 | Creek_1 | no_diameter_floor | 2021 | 1.40 | CA_SierraNevada_11_B22 | QL 1 | 2022-06-09 to 2022-06-11 | 1 | 44.4 | 19.4 | CC BY SA 4.0 | — | — | no | screen_ok (no_diameter_floor); geometry_consistent; registered |
| 0067 | FOCAL2020 | Creek_2 | no_diameter_floor | 2021 | 1.39 | CA_SierraNevada_11_B22 | QL 1 | 2022-06-11 | 1 | 45.1 | 22.9 | CC BY SA 4.0 | — | — | no | screen_ok (no_diameter_floor); geometry_consistent; conditions_admitted (unresolved); registered |
| 0068 | EP2018 | — | A | 2019 | 3.23 | CA_SierraNevada_5_2022 | QL 1 | 2022-06-02 to 2022-08-19 | 3 | 19.3 | 10.8 | CC BY 4.0 | — | — | no | registered (signal_not_admitted) |
| 0069 | STEF2007 | MOC 8 | B | 2016 | 3.46 | CA_SierraNevada_5_2022 | QL 1 | 2021-11-21 | 5 | 43.0 | 18.4 | Public domain | — | — | no | flight_admitted (gap); conditions_admitted (interval_not_covered); registered (flight_not_admitted;signal_not_admitted) |
| 0070 | STEF2007 | MOC 9 | B | 2008 | 4.27 | CA_SierraNevada_11_B22 | QL 1 | 2022-06-14 | 14 | 29.0 | 15.6 | Public domain | — | — | no | flight_admitted (gap); conditions_admitted (interval_not_covered); registered (flight_not_admitted;signal_not_admitted) |
| 0071 | STEF2007 | MOC 10 | B | 2008 | 3.80 | CA_SierraNevada_11_B22 | QL 1 | 2022-06-14 | 14 | 28.7 | 16.0 | Public domain | — | — | no | flight_admitted (gap); conditions_admitted (interval_not_covered); registered (flight_not_admitted;signal_not_admitted) |
| 0072 | STEF2007 | MOC 11 | B | 2007 | 3.74 | CA_SierraNevada_8_2022 | QL 1 | 2021-11-21 | 14 | 15.6 | 7.2 | Public domain | — | — | no | flight_admitted (gap;coverage); conditions_admitted (interval_not_covered); registered (flight_not_admitted;signal_not_admitted) |
| 0073 | STEF2018 | Unit 2 | B | 2018 | 2.98 | CA_SierraNevada_11_B22 | QL 1 | 2022-06-14 | 4 | 23.6 | 15.7 | Public domain | — | — | no | conditions_admitted (interval_not_covered); registered (signal_not_admitted) |
| 0074 | STEF2018 | Unit 5 | B | 2018 | 2.99 | CA_SierraNevada_11_B22 | QL 1 | 2022-06-14 | 4 | 24.7 | 15.9 | Public domain | — | — | no | conditions_admitted (interval_not_covered); registered (signal_not_admitted) |
| 0075 | STEF2018 | Unit 8 | B | 2018 | 2.67 | CA_SierraNevada_11_B22 | QL 1 | 2022-06-14 | 4 | 23.3 | 14.9 | Public domain | — | — | no | conditions_admitted (interval_not_covered); registered (signal_not_admitted) |
| 0076 | STEF2018 | Unit 10 | B | 2018 | 2.17 | CA_SierraNevada_11_B22 | QL 1 | 2022-06-14 | 4 | 22.0 | 14.3 | Public domain | — | — | no | conditions_admitted (interval_not_covered); registered (signal_not_admitted) |
| 0077 | STEF2018 | Unit 15 | B | 2018 | 2.52 | CA_SierraNevada_11_B22 | QL 1 | 2022-06-14 | 4 | 22.3 | 15.5 | Public domain | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted) |
| 0078 | STEF2018 | Unit 18 | B | 2018 | 2.81 | CA_SierraNevada_11_B22 | QL 1 | 2022-06-14 | 4 | 17.8 | 12.3 | Public domain | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted) |
| 0079 | STEF2018 | Unit 21 | B | 2018 | 2.95 | CA_SierraNevada_8_2022 | QL 1 | 2021-11-21 to 2022-06-14 | 3 | 24.4 | 14.6 | Public domain | — | — | no | flight_admitted (coverage); conditions_admitted (interval_not_covered); registered (flight_not_admitted;signal_not_admitted) |
| 0080 | STEF2018 | Unit 22 | B | 2018 | 2.68 | CA_SierraNevada_11_B22 | QL 1 | 2022-06-14 | 4 | 24.9 | 15.5 | Public domain | — | — | no | conditions_admitted (interval_not_covered); registered (signal_not_admitted) |
| 0081 | SJGEO2018 | — | B | 2019 | 4.00 | CA_SoCal_Wildfires_B1_2018 | QL 2 | 2018-07-29 to 2018-08-03 | 1 | 13.5 | 9.7 | CC BY 4.0 | — | — | no | flight_admitted (quality_level); registered (flight_not_admitted;signal_not_admitted) |
| 0084 | JLHZ2019 | OW2 | A | 2019 | 4.00 | CA_SierraNevada_11_B22 | QL 1 | 2022-06-10 | 3 | 15.1 | 11.0 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted) |
| 0085 | JLHZ2019 | TO1 | A | 2020 | 2.01 | CA_NorthernCA_5_B22 | QL 1 | 2022-10-15 to 2022-11-03 | 2 | 69.6 | 43.2 | CC BY 4.0 | — | — | no | conditions_admitted (interval_not_covered;leaf_off); registered (signal_not_admitted) |
| 0086 | JLHZ2019 | TO2 | A | 2020 | 2.01 | CA_NorthernCA_5_B22 | QL 1 | 2022-10-15 to 2022-11-03 | 2 | 113.1 | 58.4 | CC BY 4.0 | — | — | no | conditions_admitted (interval_not_covered;leaf_off); registered (signal_not_admitted) |
| 0088 | TNC2023 | L506 | C | 2023 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-07-01 | 1 | 38.3 | 21.0 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0089 | TNC2023 | L511 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 2 | 40.5 | 16.6 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0090 | TNC2023 | L512 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 2 | 52.5 | 23.8 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0091 | TNC2023 | L515 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 to 2021-11-08 | 2 | 51.1 | 22.0 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0092 | TNC2023 | L517 | C | 2023 | 0.29 | CA_SierraNevada_6_2022 | QL 1 | 2022-07-01 | 1 | 24.1 | 12.1 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0093 | TNC2023 | L525 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 to 2021-11-12 | 2 | 52.7 | 21.1 | CC BY SA 4.0 | — | — | no | conditions_admitted (no_usable_drone_model); registered (signal_not_admitted) |
| 0094 | TNC2023 | L502 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 | 2 | 31.6 | 16.0 | CC BY SA 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted) |
| 0095 | TNC2023 | L504 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-08 | 2 | 38.4 | 22.3 | CC BY SA 4.0 | — | — | no | conditions_admitted (snow); registered (signal_not_admitted) |
| 0096 | TNC2023 | L505 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-08 | 2 | 37.8 | 21.4 | CC BY SA 4.0 | — | — | no | conditions_admitted (disturbed;snow); registered (signal_not_admitted) |
| 0097 | TNC2023 | L507 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 to 2021-11-05 | 2 | 39.2 | 21.3 | CC BY SA 4.0 | — | — | no | conditions_admitted (unresolved); registered (signal_not_admitted) |
| 0098 | TNC2023 | L508 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 2 | 32.6 | 14.3 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0099 | TNC2023 | L521 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 | 2 | 36.9 | 16.4 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0100 | TNC2023 | L529 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 2 | 40.1 | 16.8 | CC BY SA 4.0 | — | — | no | conditions_admitted (leaf_off); registered (signal_not_admitted) |
| 0101 | TNC2023 | L536 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 to 2021-11-05 | 2 | 46.1 | 21.6 | CC BY SA 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted) |
| 0102 | TNC2023 | L519 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 | 2 | 31.3 | 16.5 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0103 | TNC2023 | L524 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 to 2021-11-05 | 2 | 33.6 | 16.4 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0104 | TNC2023 | L528 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 to 2021-11-08 | 2 | 44.3 | 19.3 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0105 | TNC2023 | L534 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 | 2 | 34.8 | 14.4 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0106 | TNC2023 | L520 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 | 2 | 27.3 | 16.2 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0107 | TNC2023 | L522 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 to 2021-11-08 | 2 | 30.4 | 12.3 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0108 | TNC2023 | L535 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 2 | 52.2 | 20.3 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0109 | TNC2023 | L539 | C | 2023 | 0.29 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 2 | 38.0 | 14.4 | CC BY SA 4.0 | — | — | no | conditions_admitted (no_usable_drone_model;leaf_off); registered (signal_not_admitted) |
| 0110 | TNC2023 | L092 | C | 2023 | 0.29 | CA_SierraNevada_1_2022 | QL 1 | 2021-11-23 | 2 | 34.0 | 17.2 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0111 | TNC2023 | L527 | C | 2023 | 0.29 | CA_SierraNevada_1_2022 | QL 1 | 2021-11-08 | 2 | 46.1 | 18.0 | CC BY SA 4.0 | — | — | no | conditions_admitted (no_usable_drone_model;leaf_off); registered (signal_not_admitted) |
| 0112 | FOCAL2023 | CA-SM03 stem map ID 3 | C | 2023 | 0.79 | CA_SierraNevada_5_2022 | QL 1 | 2021-11-20 to 2021-11-24 | 2 | 31.5 | 17.2 | CC BY SA 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted) |
| 0113 | FOCAL2023 | CA-SM05 stem map ID 4 | C | 2023 | 0.28 | CA_SierraNevada_5_2022 | QL 1 | 2021-11-17 | 2 | 33.2 | 22.1 | CC BY SA 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n;on_edge;sub_p90_m) |
| 0114 | FOCAL2023 | CA-SM05 stem map ID 3 | C | 2023 | 0.28 | CA_SierraNevada_5_2022 | QL 1 | 2021-11-17 | 2 | 33.0 | 22.4 | CC BY SA 4.0 | — | — | no | conditions_admitted (unresolved); registered (signal_not_admitted;n) |
| 0115 | CRBLDG2022 | Control_240 | D | 2022 | 1.00 | CA_SierraNevada_2_2022 | QL 1 | 2021-11-16 | 1 | 61.8 | 24.5 | CC BY 4.0 | — | — | no | registered (signal_not_admitted) |
| 0116 | CRBLDG2022 | Mech_350 | D | 2022 | 1.00 | CA_SierraNevada_2_2022 | QL 1 | 2021-11-16 | 1 | 57.3 | 24.5 | CC BY 4.0 | — | — | no | registered (signal_not_admitted) |
| 0117 | CRBLDG2022 | MechBurn_380 | D | 2022 | 1.00 | CA_SierraNevada_2_2022 | QL 1 | 2021-11-16 | 1 | 32.8 | 17.0 | CC BY 4.0 | — | — | no | registered (signal_not_admitted) |
| 0118 | CRBLDG2022 | Burn_400 | D | 2022 | 1.00 | CA_SierraNevada_2_2022 | QL 1 | 2021-11-16 | 1 | 37.2 | 17.5 | CC BY 4.0 | — | — | no | registered (signal_not_admitted) |
| 0167 | FOCAL2023 | CA-SM99 stem map ID 2 | C | 2023 | 0.28 | CA_SierraNevada_2_2022 | QL 1 | 2021-11-24 | 2 | 24.6 | 12.8 | CC BY SA 4.0 | — | — | no | geometry_consistent; conditions_admitted (disturbed); registered (signal_not_admitted;sub_p90_m) |
| 0168 | FOCAL2022 | B | C | 2021 | 0.36 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 0 | 49.1 | 20.8 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0169 | FOCAL2022 | C | C | 2021 | 0.16 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 0 | 34.4 | 14.8 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0170 | FOCAL2022 | E | C | 2021 | 0.24 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-05 | 0 | 36.2 | 15.1 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0171 | FOCAL2022 | F | C | 2021 | 0.36 | CA_SierraNevada_4_2022 | QL 1 | 2021-11-03 to 2021-11-05 | 0 | 32.9 | 15.4 | CC BY SA 4.0 | — | — | no | registered (signal_not_admitted) |
| 0186 | WADNR2023 | 3 | no_status | 2023 | 0.32 | WA_CentralWildfire_1_D22 | QL 1 | 2022-09-22 to 2022-10-01 | 1 | 15.2 | 11.0 | CC BY 4.0 | — | — | no | screen_ok (no_status); geometry_consistent; conditions_admitted (disturbed); registered |
| 0187 | WADNR2023 | 4 | no_status | 2023 | 0.32 | WA_CentralWildfire_1_D22 | QL 1 | 2022-09-19 | 1 | 21.8 | 14.2 | CC BY 4.0 | — | — | no | screen_ok (no_status); geometry_consistent; conditions_admitted (disturbed); registered |
| 0188 | WADNR2023 | 5 | no_status | 2023 | 0.21 | WA_CentralWildfire_1_D22 | QL 1 | 2022-10-11 to 2022-10-12 | 1 | 35.7 | 23.9 | CC BY 4.0 | — | — | no | screen_ok (no_status); geometry_consistent; conditions_admitted (unresolved); registered |
| 0189 | WADNR2023 | 9 | no_status | 2023 | 0.32 | WA_CentralWildfire_2_D22 | QL 1 | 2022-09-10 | 1 | 22.2 | 16.3 | CC BY 4.0 | — | — | no | screen_ok (no_status); geometry_consistent; conditions_admitted (no_usable_drone_model); registered |
| 0190 | WADNR2023 | 16 | no_status | 2023 | 0.32 | WA_CentralWildfire_1_D22 | QL 1 | 2022-09-19 | 1 | 33.2 | 19.1 | CC BY 4.0 | — | — | no | screen_ok (no_status); geometry_consistent; registered |
| 0191 | WADNR2023 | 23 | no_status | 2023 | 0.32 | WA_CentralWildfire_1_D22 | QL 1 | 2022-09-22 to 2022-10-01 | 1 | 16.4 | 13.3 | CC BY 4.0 | — | — | no | screen_ok (no_status); geometry_consistent; conditions_admitted (disturbed); registered |
| 0192 | WADNR2023 | 24 | no_status | 2023 | 0.32 | WA_CentralWildfire_1_D22 | QL 1 | 2022-09-22 to 2022-10-01 | 1 | 21.3 | 15.6 | CC BY 4.0 | — | — | no | screen_ok (no_status); geometry_consistent; conditions_admitted (unresolved); registered |
| 0193 | WADNR2023 | 31 | no_status | 2023 | 0.21 | WA_CentralWildfire_1_D22 | QL 1 | 2022-10-11 | 1 | 39.9 | 23.7 | CC BY 4.0 | — | — | no | screen_ok (no_status); geometry_consistent; conditions_admitted (unresolved); registered |
| 0194 | WADNR2023 | 35 | no_status | 2023 | 0.32 | WA_CentralWildfire_1_D22 | QL 1 | 2022-09-22 to 2022-10-01 | 1 | 16.1 | 14.3 | CC BY 4.0 | — | — | no | screen_ok (no_status); geometry_consistent; conditions_admitted (disturbed); registered |
| 0195 | WADNR2023 | 41 | no_status | 2023 | 0.21 | WA_CentralWildfire_1_D22 | QL 1 | 2022-10-11 to 2022-10-12 | 1 | 50.8 | 28.5 | CC BY 4.0 | — | — | no | screen_ok (no_status); geometry_consistent; registered |
| 0196 | WADNR2023 | 43 | no_status | 2023 | 0.21 | WA_CentralWildfire_1_D22 | QL 1 | 2022-10-11 to 2022-10-12 | 1 | 47.3 | 25.3 | CC BY 4.0 | — | — | no | screen_ok (no_status); geometry_consistent; registered |
| 0197 | MNPK2018 | IS1 | B | 2018 | 1.00 | CA_SierraNevada_13_B22 | QL 1 | 2022-06-08 to 2022-06-15 | 4 | 26.9 | 20.2 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted) |
| 0198 | MNPK2018 | IS2 | B | 2018 | 1.00 | CA_SierraNevada_13_B22 | QL 1 | 2022-06-08 to 2022-06-15 | 4 | 27.3 | 19.6 | CC BY 4.0 | — | — | no | conditions_admitted (interval_not_covered); registered (signal_not_admitted) |
| 0199 | MNPK2018 | IS3 | B | 2018 | 1.00 | CA_SierraNevada_13_B22 | QL 1 | 2022-06-08 to 2022-06-15 | 4 | 30.6 | 21.2 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted) |
| 0200 | MNPK2018 | OH1 | B | 2018 | 1.00 | CA_SierraNevada_13_B22 | QL 1 | 2022-06-15 | 4 | 24.5 | 19.4 | CC BY 4.0 | — | — | no | conditions_admitted (unresolved); registered (signal_not_admitted;on_edge) |
| 0201 | MNPK2018 | OH2 | B | 2018 | 1.00 | CA_SierraNevada_13_B22 | QL 1 | 2022-06-15 | 4 | 23.1 | 15.7 | CC BY 4.0 | — | — | no | conditions_admitted (unresolved); registered (signal_not_admitted) |
| 0202 | MNPK2018 | OH3 | B | 2018 | 1.00 | CA_SierraNevada_13_B22 | QL 1 | 2022-06-15 | 4 | 24.1 | 17.5 | CC BY 4.0 | — | — | no | conditions_admitted (unresolved); registered (signal_not_admitted) |
| 0203 | Eshom2020 | MHC_2 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 29.5 | 17.6 | CC BY 4.0 | — | — | no | conditions_admitted (unresolved); registered (signal_not_admitted;n) |
| 0204 | Eshom2020 | MHW_03 | D | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 27.2 | 17.6 | CC BY 4.0 | — | — | no | geometry_consistent; conditions_admitted (disturbed); registered (signal_not_admitted;not_run) |
| 0205 | Eshom2020 | 005_10 | C | 2021 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 1 | 21.1 | 18.5 | CC BY 4.0 | — | — | no | geometry_consistent; conditions_admitted (disturbed); registered (signal_not_admitted;n) |
| 0206 | Eshom2020 | 005_22 | C | 2021 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 1 | 44.5 | 19.4 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n;sub_p90_m) |
| 0207 | Eshom2020 | MHW_18 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 16.9 | 14.4 | CC BY 4.0 | — | — | no | conditions_admitted (unresolved); registered (signal_not_admitted;n) |
| 0208 | Eshom2020 | PPN_20 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 44.2 | 20.1 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n;on_edge;sub_p90_m) |
| 0209 | Eshom2020 | PPN_22 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 49.9 | 20.6 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n) |
| 0210 | Eshom2020 | PPN_23 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 42.9 | 20.4 | CC BY 4.0 | — | — | no | registered (signal_not_admitted;n;sub_p90_m) |
| 0211 | Eshom2020 | PPN_24 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 30.3 | 19.7 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n;sub_p90_m) |
| 0212 | Eshom2020 | PPN_25 | D | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 34.3 | 19.9 | CC BY 4.0 | — | — | no | geometry_consistent; conditions_admitted (disturbed); registered (signal_not_admitted;not_run) |
| 0213 | Eshom2020 | MHW_13 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 47.3 | 19.3 | CC BY 4.0 | — | — | no | registered (signal_not_admitted;n;sub_p90_m) |
| 0214 | Eshom2020 | MHW_15 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 36.6 | 19.6 | CC BY 4.0 | — | — | no | registered (signal_not_admitted;n) |
| 0215 | Eshom2020 | MHW_17 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 40.0 | 20.4 | CC BY 4.0 | — | — | no | registered (signal_not_admitted;n) |
| 0216 | Eshom2020 | PPN_09 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 43.1 | 19.0 | CC BY 4.0 | — | — | no | registered (signal_not_admitted;n;sub_p90_m) |
| 0217 | Eshom2020 | PPN_12 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 25.3 | 19.9 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n) |
| 0218 | Eshom2020 | PPN_13 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 40.5 | 20.7 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n;sub_p90_m) |
| 0219 | Eshom2020 | 101_24 | C | 2021 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 1 | 21.7 | 13.3 | CC BY 4.0 | — | — | no | conditions_admitted (interval_not_covered); registered (signal_not_admitted;n) |
| 0220 | Eshom2020 | 101_28 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 18.3 | 17.6 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n) |
| 0221 | Eshom2020 | 002_11 | C | 2021 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 1 | 24.8 | 19.8 | CC BY 4.0 | — | — | no | geometry_consistent; conditions_admitted (unresolved); registered (signal_not_admitted;n) |
| 0222 | Eshom2020 | 100_03 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 22.7 | 18.5 | CC BY 4.0 | — | — | no | conditions_admitted (unresolved); registered (signal_not_admitted;n) |
| 0223 | Eshom2020 | 100_06 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 33.8 | 19.4 | CC BY 4.0 | — | — | no | conditions_admitted (unresolved); registered (signal_not_admitted;n) |
| 0224 | Eshom2020 | 100_07 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 23.2 | 18.9 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n) |
| 0225 | Eshom2020 | 100_09 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 27.4 | 17.7 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n) |
| 0226 | Eshom2020 | 100_11 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 22.7 | 13.8 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n) |
| 0227 | Eshom2020 | 100_12 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 21.1 | 19.1 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n) |
| 0228 | Eshom2020 | 100_13 | D | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 15.3 | 13.5 | CC BY 4.0 | — | — | no | geometry_consistent; conditions_admitted (disturbed); registered (signal_not_admitted;not_run) |
| 0229 | Eshom2020 | 100_14 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 26.5 | 19.0 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n) |
| 0230 | Eshom2020 | 100_16 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 36.1 | 19.9 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n) |
| 0231 | Eshom2020 | 100_21 | D | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 18.8 | 18.6 | CC BY 4.0 | — | — | no | geometry_consistent; conditions_admitted (disturbed); registered (signal_not_admitted;not_run) |
| 0232 | Eshom2020 | 100_23 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 24.3 | 17.9 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n;on_edge) |
| 0233 | Eshom2020 | 100_24 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 26.7 | 19.7 | CC BY 4.0 | — | — | no | conditions_admitted (unresolved); registered (signal_not_admitted;n) |
| 0234 | Eshom2020 | 100_28 | C | 2021 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 1 | 23.7 | 19.5 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n;sub_p90_m) |
| 0235 | Eshom2020 | 100_01 | D | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 27.2 | 19.2 | CC BY 4.0 | — | — | no | geometry_consistent; conditions_admitted (disturbed); registered (signal_not_admitted;not_run) |
| 0236 | Eshom2020 | 100_02 | D | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 25.4 | 18.7 | CC BY 4.0 | — | — | no | geometry_consistent; conditions_admitted (disturbed); registered (signal_not_admitted;not_run) |
| 0237 | Eshom2020 | 100_05 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 31.5 | 18.7 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n) |
| 0238 | Eshom2020 | 100_17 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 31.2 | 18.6 | CC BY 4.0 | — | — | no | conditions_admitted (disturbed); registered (signal_not_admitted;n) |
| 0239 | Eshom2020 | 100_25 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 20.4 | 20.2 | CC BY 4.0 | — | — | no | registered (signal_not_admitted;n) |
| 0240 | Eshom2020 | 100_26 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 25.8 | 19.8 | CC BY 4.0 | — | — | no | conditions_admitted (unresolved); registered (signal_not_admitted;n) |
| 0241 | Eshom2020 | 100_27 | C | 2022 | 0.04 | CA_SierraNevada_14_B22 | QL 1 | 2022-06-08 | 0 | 26.6 | 18.6 | CC BY 4.0 | — | — | no | conditions_admitted (unresolved); registered (signal_not_admitted;n) |
| 0242 | Cambria2021 | RM10_small | nested_hyperplot | 2021 | 0.02 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 5.8 | 4.9 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); geometry_consistent; conditions_admitted (disturbed); registered |
| 0243 | Cambria2021 | RM11_small | nested_hyperplot | 2021 | 0.02 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 16.8 | 8.0 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); registered |
| 0244 | Cambria2021 | RM12_small | nested_hyperplot | 2021 | 0.02 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 8.4 | 6.6 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); geometry_consistent; conditions_admitted (unresolved); registered |
| 0245 | Cambria2021 | RM13_small | nested_hyperplot | 2021 | 0.02 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 2.3 | 2.2 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); geometry_consistent; registered |
| 0246 | Cambria2021 | RM14_small | nested_hyperplot | 2021 | 0.02 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 11.5 | 5.2 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); geometry_consistent; registered |
| 0247 | Cambria2021 | RM15_small | nested_hyperplot | 2021 | 0.02 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 4.9 | 2.7 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); conditions_admitted (unresolved); registered |
| 0248 | Cambria2021 | RM16_small | nested_hyperplot | 2021 | 0.02 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 15.7 | 8.4 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); conditions_admitted (unresolved); registered |
| 0249 | Cambria2021 | RM17_small | nested_hyperplot | 2021 | 0.02 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 4.0 | 2.4 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); conditions_admitted (unresolved); registered |
| 0250 | Cambria2021 | RM18_small | nested_hyperplot | 2021 | 0.02 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 11.2 | 5.0 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); registered |
| 0251 | Cambria2021 | RM19_small | nested_hyperplot | 2021 | 0.02 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 5.2 | 2.4 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); geometry_consistent; registered |
| 0252 | Cambria2021 | RM20_small | nested_hyperplot | 2021 | 0.02 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 5.5 | 2.9 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); geometry_consistent; conditions_admitted (disturbed); registered |
| 0253 | Cambria2021 | RM21_small | nested_hyperplot | 2021 | 0.02 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 11.5 | 5.1 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); conditions_admitted (disturbed); registered |
| 0254 | Cambria2021 | RM22_small | nested_hyperplot | 2021 | 0.02 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 5.0 | 2.6 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); registered |
| 0255 | Cambria2021 | RM9_small | nested_hyperplot | 2021 | 0.02 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 3.6 | 2.4 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); geometry_consistent; conditions_admitted (disturbed); registered |
| 0256 | Cambria2021 | RM10_large | nested_hyperplot | 2021 | 0.10 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 6.4 | 4.9 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); conditions_admitted (no_usable_drone_model); registered |
| 0257 | Cambria2021 | RM11_large | nested_hyperplot | 2021 | 0.10 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 14.8 | 7.4 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); registered |
| 0258 | Cambria2021 | RM12_large | nested_hyperplot | 2021 | 0.10 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 11.4 | 7.1 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); conditions_admitted (disturbed); registered |
| 0259 | Cambria2021 | RM13_large | nested_hyperplot | 2021 | 0.10 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 2.6 | 2.2 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); conditions_admitted (disturbed); registered |
| 0260 | Cambria2021 | RM14_large | nested_hyperplot | 2021 | 0.10 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 11.0 | 5.1 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); registered |
| 0261 | Cambria2021 | RM15_large | nested_hyperplot | 2021 | 0.10 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 4.8 | 2.6 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); conditions_admitted (unresolved); registered |
| 0262 | Cambria2021 | RM16_large | nested_hyperplot | 2021 | 0.10 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 18.2 | 8.8 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); conditions_admitted (disturbed); registered |
| 0263 | Cambria2021 | RM17_large | nested_hyperplot | 2021 | 0.10 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 4.1 | 2.4 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); conditions_admitted (disturbed); registered |
| 0264 | Cambria2021 | RM18_large | nested_hyperplot | 2021 | 0.10 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 11.9 | 5.1 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); registered |
| 0265 | Cambria2021 | RM19_large | nested_hyperplot | 2021 | 0.10 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 7.1 | 4.1 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); conditions_admitted (disturbed); registered |
| 0266 | Cambria2021 | RM20_large | nested_hyperplot | 2021 | 0.10 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 5.5 | 2.9 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); conditions_admitted (disturbed); registered |
| 0267 | Cambria2021 | RM21_large | nested_hyperplot | 2021 | 0.10 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 11.9 | 5.2 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); registered |
| 0268 | Cambria2021 | RM22_large | nested_hyperplot | 2021 | 0.10 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 5.3 | 2.7 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); conditions_admitted (disturbed); registered |
| 0269 | Cambria2021 | RM9_large | nested_hyperplot | 2021 | 0.10 | CA_FEMA_Z4_B2_2018 | QL 2 | 2018-01-27 | 3 | 3.6 | 2.4 | CC BY 4.0 | — | — | no | screen_ok (nested_hyperplot); flight_admitted (quality_level); conditions_admitted (unresolved); registered |
| 0270 | OHDS2024 | Bait_405 | B | 2019 | 1.34 | WA_Olympic_Peninsula_2013 | QL 1 | 2013-11-27 to 2013-11-28 | 6 | 11.7 | 8.7 | CC BY 4.0 | — | — | no | flight_admitted (gap); registered (flight_not_admitted;signal_not_admitted) |
| 0271 | OHDS2024 | Clavicle_302 | B | 2019 | 1.34 | — | — | — | — | — | — | CC BY 4.0 | — | — | no | flight_admitted (no_public_cloud); geometry_consistent; conditions_admitted; registered (flight_not_admitted;no_cloud;signal_not_admitted) |
| 0272 | OHDS2024 | Fresca_202 | B | 2018 | 1.42 | — | — | — | — | — | — | CC BY 4.0 | — | — | no | flight_admitted (no_public_cloud); geometry_consistent; conditions_admitted; registered (flight_not_admitted;no_cloud;signal_not_admitted) |
| 0273 | OHDS2024 | Fulton_601 | B | 2019 | 1.25 | — | — | — | — | — | — | CC BY 4.0 | — | — | no | flight_admitted (no_public_cloud); geometry_consistent; conditions_admitted; registered (flight_not_admitted;no_cloud;signal_not_admitted) |
| 0274 | OHDS2024 | Rail_103 | B | 2018 | 1.36 | — | — | — | — | — | — | CC BY 4.0 | — | — | no | flight_admitted (no_public_cloud); conditions_admitted; registered (flight_not_admitted;no_cloud;signal_not_admitted) |
| 0275 | OHDS2024 | Snow_805 | B | 2019 | 1.29 | — | — | — | — | — | — | CC BY 4.0 | — | — | no | flight_admitted (no_public_cloud); geometry_consistent; conditions_admitted; registered (flight_not_admitted;no_cloud;signal_not_admitted) |
| 0276 | OHDS2024 | Triton_703 | B | 2019 | 1.36 | — | — | — | — | — | — | CC BY 4.0 | — | — | no | flight_admitted (no_public_cloud); conditions_admitted; registered (flight_not_admitted;no_cloud;signal_not_admitted) |
| 0277 | SSMT2024 | Buckhorn | A | 2021 | 1.49 | — | — | — | — | — | — | CC BY 4.0 | — | — | no | flight_admitted (no_public_cloud); conditions_admitted; registered (flight_not_admitted;no_cloud;signal_not_admitted) |
| 0278 | SSMT2024 | Doorstop | A | 2021 | 1.55 | — | — | — | — | — | — | CC BY 4.0 | — | — | no | flight_admitted (no_public_cloud); conditions_admitted; registered (flight_not_admitted;no_cloud;signal_not_admitted) |
| 0279 | SSMT2024 | EvansCreek | A | 2021 | 1.32 | — | — | — | — | — | — | CC BY 4.0 | — | — | no | flight_admitted (no_public_cloud); conditions_admitted; registered (flight_not_admitted;no_cloud;signal_not_admitted) |
| 0280 | SSMT2024 | Floras | A | 2021 | 1.31 | — | — | — | — | — | — | CC BY 4.0 | — | — | no | flight_admitted (no_public_cloud); conditions_admitted; registered (flight_not_admitted;no_cloud;signal_not_admitted) |
| 0281 | SSMT2024 | Jammer | A | 2021 | 1.47 | — | — | — | — | — | — | CC BY 4.0 | — | — | no | flight_admitted (no_public_cloud); conditions_admitted; registered (flight_not_admitted;no_cloud;signal_not_admitted) |
| 0282 | SSMT2024 | Nortons | A | 2021 | 1.23 | OR_WWildfires_1_A22 | QL 1 | 2022-08-02 to 2022-08-03 | 1 | 20.4 | 10.1 | CC BY 4.0 | — | — | no | conditions_admitted (interval_not_covered); registered (signal_not_admitted) |
| 0283 | SSMT2024 | SliceButte | A | 2021 | 1.18 | OR_McKenzieRiver_1_2021 | QL 1 | 2021-07-06 | 0 | 24.5 | 14.0 | CC BY 4.0 | — | — | no | registered (signal_not_admitted) |
| 0284 | SSMT2024 | Soda | A | 2021 | 1.59 | — | — | — | — | — | — | CC BY 4.0 | — | — | no | flight_admitted (no_public_cloud); conditions_admitted; registered (flight_not_admitted;no_cloud;signal_not_admitted) |
| 0285 | SSMT2024 | Stone | A | 2021 | 1.31 | — | — | — | — | — | — | CC BY 4.0 | — | — | no | flight_admitted (no_public_cloud); conditions_admitted; registered (flight_not_admitted;no_cloud;signal_not_admitted) |
| 0286 | DS2024 | DS_1 | B | 2013 | 0.70 | WA_ThurstonCo_1_2021 | QL 1 | — | — | — | — | CC BY 4.0 | — | — | no | flight_admitted (no_public_cloud); conditions_admitted; registered (flight_not_admitted;no_cloud;signal_not_admitted) |
| 0287 | DS2024 | DS_2 | B | 2013 | 0.56 | WA_ThurstonCo_1_2021 | QL 1 | 2021-03-31 | 8 | 31.9 | 17.7 | CC BY 4.0 | — | — | no | flight_admitted (gap); conditions_admitted (no_usable_drone_model); registered (flight_not_admitted;signal_not_admitted) |
| 0288 | DS2024 | DS_3 | B | 2013 | 0.64 | WA_ThurstonCo_1_2021 | QL 1 | 2021-03-31 | 8 | 25.5 | 14.6 | CC BY 4.0 | — | — | no | flight_admitted (gap); conditions_admitted (no_usable_drone_model); registered (flight_not_admitted;signal_not_admitted) |
| 0289 | DS2024 | DS_4 | B | 2013 | 0.67 | — | — | — | — | — | — | CC BY 4.0 | — | — | no | flight_admitted (no_public_cloud); conditions_admitted; registered (flight_not_admitted;no_cloud;signal_not_admitted) |
| 0290 | DS2024 | DS_5 | B | 2013 | 0.79 | WA_ThurstonCo_1_2021 | QL 1 | 2021-03-31 | 8 | 36.4 | 21.7 | CC BY 4.0 | — | — | no | flight_admitted (gap); conditions_admitted (no_usable_drone_model); registered (flight_not_admitted;signal_not_admitted) |
| 0291 | DS2024 | DS_6 | B | 2013 | 0.66 | WA_ThurstonCo_1_2021 | QL 1 | — | — | — | — | CC BY 4.0 | — | — | no | flight_admitted (no_public_cloud); conditions_admitted; registered (flight_not_admitted;no_cloud;signal_not_admitted) |
| 0292 | FOCAL2025 | 203 | no_diameter_floor | 2025 | 0.50 | CA_SierraNevada_5_2022 | QL 1 | 2021-11-20 to 2021-11-24 | 4 | 42.9 | 20.1 | CC BY SA 4.0 | — | — | no | screen_ok (no_diameter_floor); conditions_admitted (no_usable_drone_model); registered |
| 0293 | FOCAL2025 | 201 | no_diameter_floor | 2025 | 0.50 | CA_SierraNevada_5_2022 | QL 1 | 2021-11-17 | 4 | 38.1 | 24.4 | CC BY SA 4.0 | — | — | no | screen_ok (no_diameter_floor); conditions_admitted (no_usable_drone_model); registered |
| 0294 | FOCAL2025 | 204 | no_diameter_floor | 2025 | 0.50 | CA_SierraNevada_5_2022 | QL 1 | 2021-11-20 | 4 | 22.8 | 13.4 | CC BY SA 4.0 | — | — | no | screen_ok (no_diameter_floor); conditions_admitted (no_usable_drone_model); registered |
| 0295 | FOCAL2025 | 200 | no_diameter_floor | 2025 | 0.50 | CA_SierraNevada_2_2022 | QL 1 | 2021-11-24 | 4 | 26.6 | 12.1 | CC BY SA 4.0 | — | — | no | screen_ok (no_diameter_floor); conditions_admitted (no_usable_drone_model); registered |

## Appendix: held-out catalogue plots

Catalogue plots with a cloud that are screened out (Screen) or have no
admitted flight, and so are never scored, registered on their best
available flight, admitted or not: 46 screened-out plots and 10 group B
plots without an admitted flight (`STEF2007` 0069 to 0072, `STEF2018` 0079,
`SJGEO2018` 0081, `OHDS2024` 0270 and `DS2024` 0287, 0288 and 0290). The
protocol's test 2 names only the first kind. One row per plot, signal and
method; `declared` is the first method, kept for the record.

| Plot | Project | Screen | Signal | Method | Stems | dx, m | dy, m | Shift, m | Residual, m | On edge | Accepted | Reason | Flight admitted |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0058 | FOCAL2020 | no_diameter_floor | height | amendment1 | 301 | 0.8 | -1.2 | 1.4 | 0.3 | no | yes | — | yes |
| 0058 | FOCAL2020 | no_diameter_floor | height | declared | 152 | 1.0 | -0.5 | 1.1 | 0.9 | no | yes | — | yes |
| 0059 | FOCAL2020 | no_diameter_floor | height | amendment1 | 151 | 4.2 | 0.3 | 4.2 | 0.3 | no | yes | — | yes |
| 0059 | FOCAL2020 | no_diameter_floor | height | declared | 76 | 5.0 | -2.0 | 5.4 | 3.2 | no | no | residual | yes |
| 0060 | FOCAL2020 | no_diameter_floor | height | amendment1 | 106 | 0.6 | -0.8 | 1.0 | 0.5 | no | yes | — | no |
| 0060 | FOCAL2020 | no_diameter_floor | height | declared | 53 | 0.0 | -0.5 | 0.5 | 1.1 | no | yes | — | no |
| 0061 | FOCAL2020 | no_diameter_floor | height | amendment1 | 127 | 2.0 | 0.4 | 2.1 | 0.5 | no | yes | — | yes |
| 0061 | FOCAL2020 | no_diameter_floor | height | declared | 64 | 2.0 | 1.5 | 2.5 | 1.6 | no | yes | — | yes |
| 0062 | FOCAL2020 | no_diameter_floor | height | amendment1 | 155 | -0.6 | 0.3 | 0.7 | 0.3 | no | yes | — | no |
| 0062 | FOCAL2020 | no_diameter_floor | height | declared | 79 | -1.5 | 1.5 | 2.1 | 1.8 | no | yes | — | no |
| 0063 | FOCAL2020 | no_diameter_floor | height | amendment1 | 282 | 0.7 | -0.6 | 0.9 | 0.3 | no | yes | — | yes |
| 0063 | FOCAL2020 | no_diameter_floor | height | declared | 141 | 2.0 | -1.0 | 2.2 | 2.4 | no | no | residual | yes |
| 0064 | FOCAL2020 | no_diameter_floor | height | amendment1 | 103 | 0.8 | -0.5 | 1.0 | 0.4 | no | yes | — | yes |
| 0064 | FOCAL2020 | no_diameter_floor | height | declared | 52 | 0.5 | -2.0 | 2.1 | 1.1 | no | yes | — | yes |
| 0065 | FOCAL2020 | no_diameter_floor | height | amendment1 | 79 | 2.2 | 0.4 | 2.2 | 0.3 | no | yes | — | yes |
| 0065 | FOCAL2020 | no_diameter_floor | height | declared | 42 | 1.0 | -1.5 | 1.8 | 1.1 | no | yes | — | yes |
| 0066 | FOCAL2020 | no_diameter_floor | height | amendment1 | 377 | 2.4 | -1.7 | 2.9 | 0.3 | no | yes | — | yes |
| 0066 | FOCAL2020 | no_diameter_floor | height | declared | 190 | 1.5 | -2.0 | 2.5 | 1.6 | no | yes | — | yes |
| 0067 | FOCAL2020 | no_diameter_floor | height | amendment1 | 159 | 2.4 | -2.7 | 3.6 | 0.4 | no | yes | — | yes |
| 0067 | FOCAL2020 | no_diameter_floor | height | declared | 81 | 2.0 | -2.5 | 3.2 | 2.1 | no | no | residual | yes |
| 0069 | STEF2007 | none | rank | amendment1 | 1,530 | -0.2 | -1.4 | 1.4 | 0.3 | no | yes | — | no |
| 0069 | STEF2007 | none | rank | declared | 1,530 | 0.5 | -1.0 | 1.1 | 1.0 | no | yes | — | no |
| 0070 | STEF2007 | none | rank | amendment1 | 3,620 | -0.7 | -1.1 | 1.3 | 0.2 | no | yes | — | no |
| 0070 | STEF2007 | none | rank | declared | 3,620 | -0.5 | -1.5 | 1.6 | 0.5 | no | yes | — | no |
| 0071 | STEF2007 | none | rank | amendment1 | 2,767 | -0.9 | -0.4 | 1.0 | 0.2 | no | yes | — | no |
| 0071 | STEF2007 | none | rank | declared | 2,767 | -1.0 | -0.5 | 1.1 | 1.0 | no | yes | — | no |
| 0072 | STEF2007 | none | rank | amendment1 | 2,518 | 2.5 | 2.8 | 3.7 | 0.5 | no | yes | — | no |
| 0072 | STEF2007 | none | rank | declared | 2,518 | 3.0 | 1.0 | 3.2 | 3.5 | no | no | contrast;residual | no |
| 0079 | STEF2018 | none | rank | amendment1 | 407 | -4.0 | -0.4 | 4.0 | 0.5 | no | yes | — | no |
| 0079 | STEF2018 | none | rank | declared | 407 | -4.0 | -0.5 | 4.0 | 1.9 | no | yes | — | no |
| 0081 | SJGEO2018 | none | rank | amendment1 | 1,137 | -1.3 | -0.4 | 1.4 | 0.6 | no | yes | — | no |
| 0081 | SJGEO2018 | none | rank | declared | 1,137 | -1.5 | 0.5 | 1.6 | 1.5 | no | yes | — | no |
| 0186 | WADNR2023 | no_status | rank | amendment1 | 22 | 3.8 | -0.3 | 3.8 | 1.3 | no | yes | — | yes |
| 0186 | WADNR2023 | no_status | rank | declared | 22 | 5.0 | -2.5 | 5.6 | 1.3 | no | yes | — | yes |
| 0187 | WADNR2023 | no_status | rank | amendment1 | 61 | 3.0 | -2.0 | 3.6 | 1.4 | no | yes | — | yes |
| 0187 | WADNR2023 | no_status | rank | declared | 61 | 1.0 | 11.0 | 11.0 | 10.7 | no | no | residual | yes |
| 0188 | WADNR2023 | no_status | rank | amendment1 | 35 | 2.6 | -2.1 | 3.3 | 0.9 | no | yes | — | yes |
| 0188 | WADNR2023 | no_status | rank | declared | 35 | 0.5 | 0.5 | 0.7 | 7.7 | no | no | residual | yes |
| 0189 | WADNR2023 | no_status | rank | amendment1 | 15 | 4.0 | -0.1 | 4.0 | 1.4 | no | yes | — | yes |
| 0189 | WADNR2023 | no_status | rank | declared | 15 | 7.0 | -1.0 | 7.1 | 10.0 | no | no | residual | yes |
| 0190 | WADNR2023 | no_status | rank | amendment1 | 79 | 2.3 | 0.4 | 2.3 | 1.0 | no | yes | — | yes |
| 0190 | WADNR2023 | no_status | rank | declared | 79 | 3.0 | 1.5 | 3.4 | 4.2 | no | no | residual | yes |
| 0191 | WADNR2023 | no_status | rank | amendment1 | 9 | 3.0 | -0.5 | 3.0 | 7.4 | no | no | n | yes |
| 0191 | WADNR2023 | no_status | rank | declared | 9 | — | — | — | — | — | no | n | yes |
| 0192 | WADNR2023 | no_status | rank | amendment1 | 19 | 4.1 | -1.6 | 4.4 | 1.0 | no | yes | — | yes |
| 0192 | WADNR2023 | no_status | rank | declared | 19 | 3.0 | -1.0 | 3.2 | 4.7 | no | no | residual | yes |
| 0193 | WADNR2023 | no_status | rank | amendment1 | 45 | 2.6 | -0.8 | 2.7 | 2.0 | no | no | sub_p90_m | yes |
| 0193 | WADNR2023 | no_status | rank | declared | 45 | 3.5 | -2.5 | 4.3 | 1.8 | no | yes | — | yes |
| 0194 | WADNR2023 | no_status | rank | amendment1 | 8 | -8.1 | 8.6 | 11.8 | 13.4 | no | no | n;sub_p90_m | yes |
| 0194 | WADNR2023 | no_status | rank | declared | 8 | — | — | — | — | — | no | n | yes |
| 0195 | WADNR2023 | no_status | rank | amendment1 | 116 | 3.9 | -0.1 | 3.9 | 0.4 | no | yes | — | yes |
| 0195 | WADNR2023 | no_status | rank | declared | 116 | 4.5 | -0.5 | 4.5 | 1.7 | no | yes | — | yes |
| 0196 | WADNR2023 | no_status | rank | amendment1 | 80 | 3.1 | -0.3 | 3.1 | 0.4 | no | yes | — | yes |
| 0196 | WADNR2023 | no_status | rank | declared | 80 | 5.0 | 0.5 | 5.0 | 4.7 | no | no | residual | yes |
| 0243 | Cambria2021 | nested_hyperplot | rank | amendment1 | 1 | — | — | — | — | — | no | n | no |
| 0243 | Cambria2021 | nested_hyperplot | rank | declared | 1 | — | — | — | — | — | no | n | no |
| 0247 | Cambria2021 | nested_hyperplot | rank | amendment1 | 1 | — | — | — | — | — | no | n | no |
| 0247 | Cambria2021 | nested_hyperplot | rank | declared | 1 | — | — | — | — | — | no | n | no |
| 0248 | Cambria2021 | nested_hyperplot | rank | amendment1 | 6 | -0.3 | -6.4 | 6.4 | 6.5 | no | no | n;sub_p90_m | no |
| 0248 | Cambria2021 | nested_hyperplot | rank | declared | 6 | — | — | — | — | — | no | n | no |
| 0249 | Cambria2021 | nested_hyperplot | rank | amendment1 | 1 | — | — | — | — | — | no | n | no |
| 0249 | Cambria2021 | nested_hyperplot | rank | declared | 1 | — | — | — | — | — | no | n | no |
| 0250 | Cambria2021 | nested_hyperplot | rank | amendment1 | 9 | -11.6 | 11.4 | 16.3 | 9.9 | no | no | n;sub_p90_m | no |
| 0250 | Cambria2021 | nested_hyperplot | rank | declared | 9 | — | — | — | — | — | no | n | no |
| 0253 | Cambria2021 | nested_hyperplot | rank | amendment1 | 2 | — | — | — | — | — | no | n | no |
| 0253 | Cambria2021 | nested_hyperplot | rank | declared | 2 | — | — | — | — | — | no | n | no |
| 0254 | Cambria2021 | nested_hyperplot | rank | amendment1 | 1 | — | — | — | — | — | no | n | no |
| 0254 | Cambria2021 | nested_hyperplot | rank | declared | 1 | — | — | — | — | — | no | n | no |
| 0256 | Cambria2021 | nested_hyperplot | rank | amendment1 | 1 | — | — | — | — | — | no | n | no |
| 0256 | Cambria2021 | nested_hyperplot | rank | declared | 1 | — | — | — | — | — | no | n | no |
| 0257 | Cambria2021 | nested_hyperplot | rank | amendment1 | 17 | -6.0 | 11.4 | 12.9 | 15.8 | no | yes | — | no |
| 0257 | Cambria2021 | nested_hyperplot | rank | declared | 17 | -3.0 | -5.0 | 5.8 | 7.1 | no | no | residual | no |
| 0258 | Cambria2021 | nested_hyperplot | rank | amendment1 | 24 | 12.0 | 1.5 | 12.1 | 14.5 | yes | no | on_edge;sub_p90_m | no |
| 0258 | Cambria2021 | nested_hyperplot | rank | declared | 24 | 11.0 | 6.0 | 12.5 | 10.8 | no | no | residual | no |
| 0259 | Cambria2021 | nested_hyperplot | rank | amendment1 | 12 | 12.0 | -7.9 | 14.4 | 19.7 | yes | no | on_edge;sub_p90_m | no |
| 0259 | Cambria2021 | nested_hyperplot | rank | declared | 12 | — | — | — | — | — | no | n | no |
| 0260 | Cambria2021 | nested_hyperplot | rank | amendment1 | 32 | -2.7 | -9.8 | 10.2 | 9.6 | no | yes | — | no |
| 0260 | Cambria2021 | nested_hyperplot | rank | declared | 32 | -9.5 | -1.0 | 9.6 | 13.9 | no | no | residual | no |
| 0261 | Cambria2021 | nested_hyperplot | rank | amendment1 | 17 | 0.8 | 0.9 | 1.2 | 0.9 | no | yes | — | no |
| 0261 | Cambria2021 | nested_hyperplot | rank | declared | 17 | 0.5 | 1.0 | 1.1 | 3.0 | no | no | residual | no |
| 0262 | Cambria2021 | nested_hyperplot | rank | amendment1 | 52 | 2.2 | 9.5 | 9.8 | 10.3 | no | no | sub_p90_m | no |
| 0262 | Cambria2021 | nested_hyperplot | rank | declared | 52 | -11.5 | 2.5 | 11.8 | 14.8 | no | no | residual | no |
| 0263 | Cambria2021 | nested_hyperplot | rank | amendment1 | 18 | 1.6 | 0.1 | 1.6 | 2.7 | no | yes | — | no |
| 0263 | Cambria2021 | nested_hyperplot | rank | declared | 18 | 2.0 | 2.0 | 2.8 | 13.2 | no | no | residual | no |
| 0264 | Cambria2021 | nested_hyperplot | rank | amendment1 | 54 | 2.0 | 4.3 | 4.7 | 1.9 | no | yes | — | no |
| 0264 | Cambria2021 | nested_hyperplot | rank | declared | 54 | -4.0 | -2.0 | 4.5 | 4.8 | no | no | residual | no |
| 0265 | Cambria2021 | nested_hyperplot | rank | amendment1 | 36 | 6.1 | -9.8 | 11.5 | 13.1 | no | no | sub_p90_m | no |
| 0265 | Cambria2021 | nested_hyperplot | rank | declared | 36 | 5.5 | -10.5 | 11.9 | 17.1 | no | no | residual | no |
| 0266 | Cambria2021 | nested_hyperplot | rank | amendment1 | 26 | -3.2 | -7.1 | 7.8 | 8.0 | no | no | sub_p90_m | no |
| 0266 | Cambria2021 | nested_hyperplot | rank | declared | 26 | -3.5 | -5.0 | 6.1 | 15.7 | no | no | residual | no |
| 0267 | Cambria2021 | nested_hyperplot | rank | amendment1 | 42 | -1.5 | -12.0 | 12.1 | 11.9 | yes | no | on_edge;sub_p90_m | no |
| 0267 | Cambria2021 | nested_hyperplot | rank | declared | 42 | -12.0 | 4.0 | 12.6 | 14.5 | yes | no | on_edge;residual | no |
| 0268 | Cambria2021 | nested_hyperplot | rank | amendment1 | 47 | -1.1 | 12.0 | 12.0 | 9.3 | yes | no | on_edge;sub_p90_m | no |
| 0268 | Cambria2021 | nested_hyperplot | rank | declared | 47 | -7.5 | 4.0 | 8.5 | 5.9 | no | no | residual | no |
| 0269 | Cambria2021 | nested_hyperplot | rank | amendment1 | 2 | — | — | — | — | — | no | n | no |
| 0269 | Cambria2021 | nested_hyperplot | rank | declared | 2 | — | — | — | — | — | no | n | no |
| 0270 | OHDS2024 | none | rank | amendment1 | 633 | -0.6 | -3.7 | 3.8 | 8.4 | no | yes | — | no |
| 0270 | OHDS2024 | none | rank | declared | 633 | 7.0 | -1.0 | 7.1 | 8.1 | no | no | residual | no |
| 0287 | DS2024 | none | rank | amendment1 | 439 | 1.4 | -0.1 | 1.4 | 0.1 | no | yes | — | no |
| 0287 | DS2024 | none | rank | declared | 439 | 0.5 | -1.0 | 1.1 | 0.7 | no | yes | — | no |
| 0288 | DS2024 | none | rank | amendment1 | 469 | 1.4 | -0.7 | 1.6 | 0.2 | no | yes | — | no |
| 0288 | DS2024 | none | rank | declared | 469 | 2.0 | -0.5 | 2.1 | 0.5 | no | yes | — | no |
| 0290 | DS2024 | none | rank | amendment1 | 435 | 1.1 | -1.0 | 1.5 | 0.1 | no | yes | — | no |
| 0290 | DS2024 | none | rank | declared | 435 | 1.5 | -1.5 | 2.1 | 0.7 | no | yes | — | no |
| 0292 | FOCAL2025 | no_diameter_floor | height | amendment1 | 137 | 2.7 | -1.9 | 3.3 | 0.4 | no | yes | — | yes |
| 0292 | FOCAL2025 | no_diameter_floor | height | declared | 70 | 1.0 | -2.5 | 2.7 | 1.0 | no | yes | — | yes |
| 0292 | FOCAL2025 | no_diameter_floor | rank | amendment1 | 137 | 2.9 | -1.4 | 3.2 | 0.5 | no | yes | — | yes |
| 0292 | FOCAL2025 | no_diameter_floor | rank | declared | 137 | 3.5 | 0.0 | 3.5 | 1.5 | no | yes | — | yes |
| 0293 | FOCAL2025 | no_diameter_floor | height | amendment1 | 47 | -2.8 | -3.9 | 4.8 | 1.3 | no | yes | — | yes |
| 0293 | FOCAL2025 | no_diameter_floor | height | declared | 24 | -4.5 | -3.5 | 5.7 | 2.7 | no | no | residual | yes |
| 0293 | FOCAL2025 | no_diameter_floor | rank | amendment1 | 46 | -3.2 | -3.6 | 4.8 | 0.7 | no | yes | — | yes |
| 0293 | FOCAL2025 | no_diameter_floor | rank | declared | 46 | -2.5 | -2.5 | 3.5 | 2.6 | no | no | residual | yes |
| 0294 | FOCAL2025 | no_diameter_floor | height | amendment1 | 58 | 5.0 | -3.1 | 5.9 | 1.5 | no | yes | — | yes |
| 0294 | FOCAL2025 | no_diameter_floor | height | declared | 29 | 3.0 | -3.5 | 4.6 | 1.7 | no | yes | — | yes |
| 0294 | FOCAL2025 | no_diameter_floor | rank | amendment1 | 57 | 5.2 | -3.6 | 6.4 | 2.9 | no | no | sub_p90_m | yes |
| 0294 | FOCAL2025 | no_diameter_floor | rank | declared | 57 | 2.5 | -4.0 | 4.7 | 6.0 | no | no | residual | yes |
| 0295 | FOCAL2025 | no_diameter_floor | height | amendment1 | 80 | -2.9 | -8.1 | 8.7 | 1.3 | no | yes | — | yes |
| 0295 | FOCAL2025 | no_diameter_floor | height | declared | 40 | -1.5 | -9.0 | 9.1 | 3.5 | no | no | residual | yes |
| 0295 | FOCAL2025 | no_diameter_floor | rank | amendment1 | 80 | -3.0 | -8.3 | 8.9 | 1.4 | no | yes | — | yes |
| 0295 | FOCAL2025 | no_diameter_floor | rank | declared | 80 | -2.5 | -8.0 | 8.4 | 3.2 | no | no | residual | yes |
