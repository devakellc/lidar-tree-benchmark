# Reference Population and Fire History Audit

Checked on 17 November 2026. This audit was added after an internal review of
the paper, after all results were known. It changes no reference, rule or
score. It describes the field reference of the headline `adopted` population
of the [frozen-clip study](frozen-clips-results.md) (106 plots, 2,525
reference records) and overlays every plot on public wildfire perimeters.
[`reference_population_audit.R`](../scripts/reference_population_audit.R)
reads the sealed frozen root, the ground truth and the cached NEON
woody-vegetation tables (RELEASE-2026) without writing to them. It stops
unless its records equal the frozen population record for record and every
record's scored NEON measurement re-derives field by field.

**Findings.**

- **A reference record is one bole, not one tree.** NEON tags each additional
  bole of a multi-bole individual with the individual's ID plus a letter
  (`NEON.PLA.D17.SJER.00064A`), and every bole that passes the population
  rules is a reference. 37 records are additional boles of 20 individuals;
  27 of them are at SJER, where the 57 records belong to 31 individuals.
- **Crown class comes from NEON's canopy position for 2,462 records.** The
  height-quantile fallback classed 2 (at ABBY); 61 records have no class.
- **62 records have no field height**, 34 of them additional boles.
- **References were measured from 2017 to 2024**: 1,318 in 2021, 525 before
  and 682 after. SJER has no 2021 measurement.
- **Six SOAP plots lie inside the 2020 Creek Fire as CAL FIRE maps it, none
  as the NIFC sources map it.** The two copies have the same shape about
  0.9 km apart. Three of the six (22 stems) were measured only in 2019,
  before a fire that preceded the July 2021 flight; the other three were
  re-measured after it. The 2025 Garnet Fire contains six TEAK plots, after
  the flight and their references. No wildfire perimeter of 2015–2025
  contains a plot centroid at SJER, WREF or ABBY.

## Reference records

A record is the NEON measurement of one tagged bole. The population rules (a
live, mapped tree of at least 10 cm DBH, inside the nominal core of a plot
holding at least six such stems in all) apply to each bole, so a multi-bole
individual contributes every bole that passes them. Here a multi-bole
individual is one with an additional-bole record in the reference; its
records include the primary bole when that passes too (11 of SJER's 12).

| Site | Plots | Records | Individuals | Additional-bole records | Multi-bole individuals | Their records | No height | No height, additional boles |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SJER | 6 | 57 | 31 | 27 | 12 | 38 | 29 | 27 |
| SOAP | 18 | 231 | 231 | 0 | 0 | 0 | 3 | 0 |
| TEAK | 19 | 374 | 370 | 4 | 2 | 6 | 6 | 4 |
| WREF | 38 | 1,063 | 1,058 | 5 | 5 | 10 | 24 | 3 |
| ABBY | 25 | 800 | 799 | 1 | 1 | 2 | 0 | 0 |
| All | 106 | 2,525 | 2,489 | 37 | 20 | 56 | 62 | 34 |

The suffix letters in the reference run from A to F. NEON's growth form is
"multi-bole tree" on 36 of the 37 additional-bole records; WREF
`04424A` is recorded as a single-bole tree beside its own primary record.
The growth form marks 143 records as multi-bole, most of them primaries whose
other boles are thinner than 10 cm or outside the core (26 at SOAP, where no
additional bole is a reference). Each bole is scored as its own stem, and a
detected apex can match at most one of them.

## Crown classes

`neon_ground_truth.R` maps NEON's `canopyPosition` to crown classes:

| NEON canopy position | Crown class |
| --- | --- |
| Open grown, Full sun | dominant |
| Partially shaded | codominant |
| Mostly shaded | intermediate |
| Full shade | suppressed |

A stem without a mapped canopy position but with a height is classed by the
height percentiles of such stems in its plot (up to the 33rd suppressed, to
the 66th intermediate, to the 90th codominant, above it dominant), counted
over all mapped stems before the population rules, when the plot holds at
least four of them. Other stems stay unclassed: they count in overall recall
and in no crown class.

| Site | Canopy position | Height fallback | No class | Dominant | Codominant | Intermediate | Suppressed |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SJER | 28 | 0 | 29 | 19 | 8 | 1 | 0 |
| SOAP | 228 | 0 | 3 | 71 | 113 | 37 | 7 |
| TEAK | 368 | 0 | 6 | 86 | 230 | 50 | 2 |
| WREF | 1,042 | 0 | 21 | 103 | 535 | 376 | 28 |
| ABBY | 796 | 2 | 2 | 68 | 639 | 88 | 3 |
| All | 2,462 | 2 | 61 | 347 | 1,525 | 552 | 40 |

The two fallback records at ABBY became one codominant and one suppressed
stem. Of the 61 unclassed records, 32 are additional boles: NEON records
canopy position, like height, on the primary bole.

## Heights

62 records have no field height: 34 additional boles and 28 others (21 of
them at WREF). The matcher applies its height-consistency gate only to a
reference with a height, so these 62 are matched on position alone.

## Measurement years

Each record is scored with its NEON measurement nearest 2021 within four
years. Records by measurement year:

| Site | 2017 | 2018 | 2019 | 2020 | 2021 | 2022 | 2023 | 2024 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SJER | 0 | 0 | 0 | 0 | 0 | 33 | 1 | 23 |
| SOAP | 0 | 0 | 86 | 10 | 51 | 0 | 84 | 0 |
| TEAK | 0 | 0 | 0 | 0 | 183 | 181 | 4 | 6 |
| WREF | 1 | 0 | 98 | 144 | 534 | 283 | 2 | 1 |
| ABBY | 0 | 1 | 184 | 1 | 550 | 7 | 3 | 54 |
| All | 1 | 1 | 368 | 155 | 1,318 | 504 | 94 | 84 |

SJER has no 2021 census: its references were measured 9 months to 3.6 years
after its flight of 31 March 2021 (January 2022 to November 2024). The other
flights were in July 2021.

## Fire history

**Sources**, queried on 17 November 2026 (11:52–11:55 UTC) with the bounding
box of each site's plot centroids plus 0.01 degree, for fires of 2015–2025:

| Source | ArcGIS feature layer | Layer name | Used for |
| --- | --- | --- | --- |
| NIFC Interagency Fire Perimeter History | `https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/InteragencyFirePerimeterHistory_2010s_Read_Only/FeatureServer/0` and `.../InterAgencyFirePerimeterHistory_2020s_Read_Only/FeatureServer/0` | InteragencyFirePerimeterHistory | Fire years 2015–2024, all sites; no alarm or containment dates |
| NIFC WFIGS Interagency Perimeters | `https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/WFIGS_Interagency_Perimeters/FeatureServer/0` | Perimeters | Fires discovered 2016–2025, all sites; discovery and containment dates |
| CAL FIRE FRAP California Fire Perimeters | `https://services1.arcgis.com/jUJYIo9tSA7EHvfZ/arcgis/rest/services/California_Historic_Fire_Perimeters/FeatureServer/0` | California Fire Perimeters (all) | Fire years 2015–2025, California sites; alarm and containment dates |

The all-years view of the NIFC history omitted most fires from 2020 on, the
Creek Fire among them, so its decade layers are used. Perimeters are read as
Esri JSON, whose ring orientation keeps unburned islands as holes. The overlay
runs in each site's UTM frame, and each of the 361 plot-and-layer pairs was
also put to the service as a point query; all 361 answers agree with the
overlay. Fire dates are CAL FIRE's where it holds the fire, else WFIGS's.
The 2021 flight days come from the
[census-support evidence](../docs/census-support-evidence.json); the earlier
sparse flights are known by month (SJER March 2017, SOAP and TEAK June 2018).

**Fires.**

| Fire | Dates | Size (CAL FIRE) | Sources |
| --- | --- | ---: | --- |
| Creek, 2020 | 4 September – 24 December 2020 | 379,842 acres | CAL FIRE, NIFC history, WFIGS; same dates in CAL FIRE and WFIGS |
| Blue, 2021 | 29 June – 3 July 2021 | 291 acres | CAL FIRE, NIFC history, WFIGS; same dates in CAL FIRE and WFIGS |
| Garnet, 2025 | 24 August – 23 October 2025 | 60,019 acres | CAL FIRE, WFIGS (no containment date) |

**Plot centroids inside a perimeter.** In the timing column, "before the
flight" means the fire preceded the site's 2021 flight.

| Site | Plot | Type | Stems | Fire | Centroid: CAL FIRE / NIFC and WFIGS | References measured | Timing |
| --- | --- | --- | ---: | --- | --- | --- | --- |
| SJER | none | | | | | | |
| SOAP | SOAP_002 | distributed | 10 | Creek | inside / 363 m outside | 10 June 2019 | references predate a fire before the flight |
| SOAP | SOAP_008 | distributed | 6 | Creek | inside / 329 m outside | 22 July 2019 | references predate a fire before the flight |
| SOAP | SOAP_013 | distributed | 6 | Creek | inside / 256 m outside | 12 June 2019 | references predate a fire before the flight |
| SOAP | SOAP_046 | tower | 16 | Creek | inside / 529 m outside | December 2021 – September 2023 | re-measured after a fire before the flight |
| SOAP | SOAP_050 | tower | 27 | Creek | inside / 637 m outside | October 2023 | re-measured after a fire before the flight |
| SOAP | SOAP_055 | tower | 13 | Creek | inside / 600 m outside | October 2021 – October 2023 | re-measured after a fire before the flight |
| TEAK | TEAK_001, 002, 006, 013, 015, 019 | distributed | 81 | Garnet | inside in both | June – August 2022 | fire after the flight and the references |
| WREF | none | | | | | | |
| ABBY | none | | | | | | |

Every nominal core holding such a centroid lies wholly inside the perimeter,
and no perimeter crosses a core without containing its centroid.

**Plot centroids within 250 m of a perimeter**, inside none:

| Site | Plot | Type | Stems | Fire | Distance to the edge | References measured | Timing |
| --- | --- | --- | ---: | --- | ---: | --- | --- |
| SJER | SJER_051 | tower | 6 | Highway 41 Burn, prescribed, yearly 2019–2024 | 206 m | November 2024 | dated by year only |
| SOAP | SOAP_020 | distributed | 10 | Blue | 15 m | June 2019 | references predate a fire before the flight |
| SOAP | SOAP_049 | tower | 8 | Blue | 63 m | October 2023 | re-measured after the fire |
| SOAP | SOAP_057 | tower | 6 | Creek | 74 m (CAL FIRE), 924 m (NIFC) | December 2021 – October 2023 | re-measured after the fire |
| SOAP | SOAP_048 | tower | 31 | Creek | 124 m (CAL FIRE), 951 m (NIFC) | December 2021 – October 2023 | re-measured after the fire |
| SOAP | SOAP_009 | distributed | 5 | Blue | 165 m | June 2019 | references predate a fire before the flight |
| SOAP | SOAP_031 | tower | 34 | Blue | 182 m | October 2021 – September 2023 | re-measured after the fire |
| SOAP | SOAP_021 | distributed | 8 | Creek | 183 m (CAL FIRE), 1,102 m (NIFC) | July 2019 | references predate a fire before the flight |
| SOAP | SOAP_003 | distributed | 5 | Blue | 227 m | June 2019 | references predate a fire before the flight |
| TEAK | TEAK_007 | distributed | 8 | Garnet | 25 m | July 2022 | fire after the flight and the references |
| TEAK | TEAK_017 | distributed | 12 | Garnet | 57 m | August 2022 | fire after the flight and the references |

WREF and ABBY have no perimeter of 2015–2025 within their boxes. Every
perimeter near SJER is a prescribed burn in the NIFC history.

## The two Creek Fire perimeters

CAL FIRE's copy and the NIFC copies (the history and WFIGS hold the same
geometry) cover 1,537.5 and 1,537.6 km² but differ over 203 km². Moving the
NIFC copy 246 m east and 887 m north, onto CAL FIRE's centroid, leaves a
difference of 0.74 km²: one copy is displaced by about 0.9 km. Under CAL
FIRE's placement six adopted plots are inside; under the NIFC placement none
is, the nearest centroid lying 256 m outside. The Blue and Garnet perimeters
agree across their sources.

NEON individual measurement records (`vst_apparentindividual`) dated after the
fire's start exist at 18 SOAP plots (7 adopted, 11 others), and each plot has
records whose remarks or status mention fire, burning or scorch. In the cached
tables, mapping-and-tagging records (`vst_mappingandtagging`), which the audit
does not read for remarks, postdate the fire's start at 39 SOAP plots (17 of the
18 adopted ones); two of them, at SOAP_052, mention burning. With CAL FIRE's
placement 14 of the 18 centroids lie inside the Creek or Blue perimeter and the
other 4 within 63 to 182 m of one. With the NIFC placement only the four inside
the Blue perimeter do; the others lie up to 924 m from either. The field remarks
fit CAL FIRE's placement better. The audit does not establish which copy is
correctly georeferenced, and a scorch remark does not date the fire that left
it.

## What it means for the benchmark

- **References that predate a fire before the flight.** SOAP_002, SOAP_008
  and SOAP_013 (distributed, 22 stems measured in June and July 2019) lie
  inside CAL FIRE's Creek perimeter. A tree killed or consumed there before
  the flight of 12–13 July 2021 is still a live reference and is scored as a
  missed stem. The cached NEON tables hold no measurement of these plots
  after 2019; their mapping-and-tagging records from 2024 and 2025 show that
  NEON has revisited them, so a later release may hold post-fire
  measurements. All 11 distributed SOAP plots (96 stems) were measured only
  before the Creek Fire, from June 2019 to March 2020. Four of the other
  eight lie within 250 m of a perimeter; SOAP_020 is 15 m outside the Blue
  Fire, which ended nine days before the flight.
- **Re-measured after the fire.** SOAP_046, SOAP_050 and SOAP_055 (tower, 56
  stems) were measured from October 2021 to October 2023. Their references
  postdate the fire, so trees that died in it are not references. All 56
  also postdate the flight of 12–13 July 2021: the earliest scored record of
  each plot is dated 22 December 2021, 3 October 2023 and 12 October 2021.
- **Status transitions.** On the seven SOAP tower plots re-measured after the
  fire, every individual live at its last record before the fire and
  re-measured after it was last recorded in 2015. Of those individuals, 36
  of 119 (30%) on the three plots inside the perimeter were not
  live at their first record after the fire, against 48 of 139 (35%) on the
  four SOAP tower plots outside it (stems of at least 10 cm DBH: 16 of 78
  and 41 of 112). The interval spans the 2012–2016 drought and its beetle
  mortality, and the outside plots carry fire remarks too, so these
  transitions do not isolate fire mortality.
- **Sparse-flight comparison.** All 18 SOAP plots belong to the native
  sparse-flight comparison (209 of its 586 stems). The six plots inside CAL
  FIRE's perimeter of the Creek Fire hold 62 of those stems; that fire burned
  between the June 2018 and July 2021 flights, and the Blue Fire fell between
  them too. On those plots the two clouds may differ for reasons other than
  density, and the stems live in both references were last measured before the
  fire on the three distributed plots. Under the NIFC placement no comparison
  plot is inside a perimeter. No wildfire perimeter contains or comes within
  250 m of the 4 SJER and 17 TEAK comparison plots between their flights; the
  prescribed burns 206 m from SJER_051 in 2019 and 2020 fall between SJER's
  flights.
- **TEAK.** The Garnet Fire burned after the flight and after the 2022
  references, so it does not affect this benchmark; a later TEAK flight or
  census would need it.

## Limits

- A perimeter is not burn severity. It encloses unburned and lightly burned
  ground, and a centroid inside it says nothing about what burned inside the
  plot. No burn-severity product was used.
- The Creek Fire's placement differs by about 0.9 km between sources, so
  which SOAP plots it reached is uncertain.
- The NIFC history carries no alarm or containment dates, so the SJER burns
  are dated by year only; the sparse flights are dated by month.
- Status transitions count NEON individual IDs (boles), and only those
  recorded on both sides of the fire.
- The overlay uses nominal plot cores and centroids, not censused subplots.
- The NEON tables are the cached RELEASE-2026 data.

## Reproduction

```sh
CLAUDE_JOB_DIR=work/paper_runs Rscript scripts/reference_population_audit.R
# again, offline, from the cached perimeter responses:
CLAUDE_JOB_DIR=work/paper_runs Rscript scripts/reference_population_audit.R OFFLINE=1
Rscript -e 'testthat::test_file("tests/testthat/test-reference-population-audit.R")'
```

Inputs: the sealed root `work/neon/frozen_2021`, the ground truth, plot
centroids and NEON tables under `work/paper_runs/neon/<SITE>/`, and the
sparse-epoch roots under `work/sparse_2017` and `work/sparse_2018`. Outputs
go to `work/paper_runs/reference_audit/`: the reference records, summaries
and measurement years; per-plot years and fire relations; the fire hits,
near plots, perimeters, source offsets, field remarks and status
transitions; the log; and `fire_cache/`, the raw service responses with a
manifest of URLs, access times and SHA-256 digests. With the cache in place
the script needs no network; without cache or network it stops.
