# TEAK-focused validation eligibility audit

Reviewed 28 September 2026. The intended deployment is USGS-like airborne
LiDAR in forests resembling NEON Lower Teakettle. Actual deployment tiles,
measured density and acquisition season have not yet been supplied.

**Prioritize a TEAK-like native ALS detection study. Seven locally unscored
TEAK plots have a 2022 full-growth-form census, but none is evaluation-ready.**
Five contain only 29 target bole records before geometry and quality checks;
two contain no records meeting that target definition. This is a small,
within-site transfer opportunity, not enough evidence for a universal router
or an independent crown-mask benchmark. Dense external instance datasets
remain supplementary to this deployment-focused track.

## Acquisition evidence

[Lower Teakettle](https://www.neonscience.org/field-sites/teak) is a mixed-conifer
site in mountainous Sierra Nevada terrain. Forest similarity is useful, but
does not establish comparable LiDAR sampling or reference completeness.

The current [NEON site inventory](https://data.neonscience.org/api/v0/sites/TEAK)
lists discrete-return LiDAR in June 2013, June 2017, June 2018, June 2019,
July 2021, July 2023 and June 2024. It lists **no 2022 NEON LiDAR**. Vegetation
structure data include June through September 2022. Published availability is
site/month metadata, not proof of cloud coverage at every plot.

The cached RELEASE-2026 field records span 2015 and 2021–2024. The fresh API
also lists July–September 2025 field data as provisional; those records were
not inspected. This audit prioritizes 2022 because it matches the documented
USGS flight year, not because it is the newest or only possible reference
epoch. Other epochs would require their own acquisition and support audits.

A fresh EPT boundary-index intersection finds one candidate project,
`CA_SierraNevada_14_B22`, covering all 40 archived TEAK plot centroids.
Centroid coverage does not prove complete buffered-cloud coverage. The
[USGS project report](https://rockyweb.usgs.gov/vdelivery/Datasets/Staged/Elevation/metadata/CA_SierraNevada_B22/USGS_CA_SierraNevada_B22_Project_Report.pdf),
page 4, identifies this work unit as **QL1**, collected from 4 June through
23 September 2022. The
[work-unit technical report](https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/metadata/CA_SierraNevada_B22/CA_SierraNevada_14_B22/reports/140G0222F0176_CA_SierraNevada_2022_WU_300462_WU14_Report_Revision.pdf),
printed pages 1, 2 and 21, documents flight-day ranges, NAD83(2011) UTM 11N
with NAVD88/GEOID18 elevations, and a work-unit mean of 22.03 first returns/m².
These project aggregates do not establish plot-specific timing or density.

The audit reads only density and plot-identity columns from historical CSVs:

| Acquisition and inspected scope | First returns/m²: min / median / max | All returns/m²: min / median / max |
| --- | --- | --- |
| NEON 2021 native sweep, 20 historical plots | 7.21 / 11.65 / 17.76 | 12.75 / 19.16 / 25.35 |
| USGS 2022 native clips, 19 historical plots | 21.41 / 31.38 / 43.93 | 38.56 / 62.53 / 93.75 |

These are historical measurements on different plot sets, not a new matched
comparison or measurements of the seven candidates. The
[USGS quality-level specification](https://www.usgs.gov/ngp-standards-and-specifications/lidar-base-specification-tables)
sets minimum nominal pulse densities; a QL2 label does not mean exactly two
pulses/m². Measure `frdens` and `pdens` separately on admitted metric support.
Decimation remains a controlled simulation, not native sparse acquisition.

The EPT header uses EPSG:3857. New extracts need a justified metric horizontal
frame and explicit field-to-cloud datum handling. WGS84 NEON field metadata
and NAD83(2011) source-cloud coordinates cannot be declared aligned merely by
assigning the same EPSG label. Absolute NAVD88 elevations also require ground
normalization before an above-ground-height comparison.

## Prior use and candidate reference support

The local inventory has 40 plot centroids. Plot identifiers in derived CSVs,
frozen inputs, prediction caches and instance-output paths show prior use of
20 plots. Existing calibration/validation splits within those 20 do not
make them untouched for a new selection study. Later acquisitions of the
same plots are repeated biological populations, not fresh spatial holdouts.

Twenty other plots have no membership evidence in the scanned local result
and cache inventory. This is a bounded local finding, not proof of absence
from every prior experiment or upstream checkpoint training. Thirteen are
tower plots with 2022 dendrometer-only events; those events cannot establish
a complete detection census. The seven remaining plots are distributed:

| Plot | Census date in 2022 | Target bole records | Invalid/missing positive height | Cached / required subplot corners |
| --- | --- | --- | --- | --- |
| TEAK_004 | 29 June | 0 | 0 | 0 / 9 |
| TEAK_005 | 6 July | 13 | 3 | 4 / 9 |
| TEAK_010 | 13 July | 4 | 0 | 2 / 9 |
| TEAK_016 | 16 August | 4 | 0 | 2 / 9 |
| TEAK_018 | 7 September | 4 | 0 | 2 / 9 |
| TEAK_024 | 7 September | 0 | 0 | 0 / 9 |
| TEAK_025 | 30 June | 4 | 1 | 2 / 9 |

Target records are live single-bole or multi-bole measurements with DBH at
least 10 cm, joined by plot, census event and measurement year. They are not
unique-tree counts, complete all-tree references or admitted scoring
numerators. The seven events report 400 m² and internally consistent sampled
subplot identifiers. Matching nominal area does not establish surveyed
geometry. Corner counts indicate cached identifier availability only; they
do not validate coordinate accuracy or boundary uncertainty.

The five positive candidate plots contain 29 target records, of which 25 have
finite positive height. Dropping the other four silently would change the
reference population. No candidate has all required corners cached. Latest
mapping dates for the eight target records on TEAK_018 and TEAK_025 postdate
the census event; mapping history and persistence need review before their
coordinates can represent the acquisition epoch. Zero target records on
TEAK_004/024 do not establish absence of smaller trees or vegetation and are
not automatically valid negative-control plots.

Across all 40 plots, the cached RELEASE-2026 field tables contain 25
`allGrowthForms` events in 2022: 20 distributed events at 400 m² and five
tower events at 800 m². The other 15 events are dendrometer-only. Those 25
full-growth-form events contain 419 target records, 13 without valid positive
height, and four with unresolved measurement-subplot identifiers. These are
source-record diagnostics, before mapping, geometry and quality exclusions.
Only three full-growth-form events have every required corner identifier in
the historical point-location cache.

The historical nominal-box audit reproduces 436 TEAK reference records:
204 under partial-area events, 27 under dendrometer-only events, 19 with
unresolved event joins and 186 still needing a footprint audit. This different
population includes historical nearest-year references; it must not be
combined with the exact-2022 counts above. Its detector metrics were not
recomputed. See the [reference-support findings](neon-reference-support-results.md).

## Decision and next executable study

Proceed with support reconstruction for the **seven distributed candidates**
and an explicitly separated historical development population. Preserve all
seven through the audit, including zero-target candidates and missing-height
cases; select support using declared metadata rules, never detector outcomes.
The immediate unresolved work is:

1. Retrieve surveyed corner and mapping history metadata; resolve event-level
   census population, incomplete heights, bole versus individual identity,
   boundary margins and field-to-cloud positional compatibility.
2. Resolve 2022 USGS tile/flight dates against the June–September census dates.
   Same-year overlap alone does not establish temporal agreement.
3. Profile the user's representative tiles, then measure candidate native
   first/all-return density, ground support and vertical frame. The covering
   QL1 project may be denser than the intended deployment data.
4. Check exact installed-checkpoint exposure, spatial buffers and shared
   acquisition context. Declare whole-plot development/evaluation membership
   before inference. Keep the seven candidates unscored while resolving these
   gates; do not divide their trees into tuning and test subsets.

If admitted, the bounded comparison should retain corrected whole-scene FF3D,
SAT, multichm and CHM-VWF on identical supported plots. Develop settings and
fresh target-compatible calibration on admitted historical support. Freeze
selection before candidate evaluation; report per-plot counts, pooled
reference-relative detection metrics and uncertainty. Seven small plots at
one site cannot establish broad site transfer, and only five currently have
positive target records. A second independent TEAK-like forest/project is
needed for a stronger deployment-generalization claim.

Field stems can support a qualified detection comparison. They cannot validate
point-instance masks, full crown extent, all-tree precision, DBH or biomass.
Retain FGI-EMIT and the
[external instance-dataset shortlist](validation-dataset-eligibility.md) for
separate annotation-supported diagnostics. The existing FGI-EMIT FF3D policy
and old NEON adapter rankings do not select a TEAK deployment winner.

## Reproduction and evidence

The [offline audit](../scripts/audit_teak_validation.R) reads cached field
metadata, historical plot membership and density columns, and archived public
metadata. It never invokes a detector, reads prediction arrays or regenerates
scores. Input SHA-256 hashes, derived CSVs and an output receipt are written
to a fresh directory; existing output directories are rejected. Inputs are
hashed before their first read and checked again before completion. The full
scanned CSV and artifact path lists are recorded and checked for additions or
removals; prediction-array contents are not hashed.

```sh
Rscript scripts/audit_teak_validation.R \
  SOURCE=/home/alex/projects/lidar_tree_benchmarks/work \
  METADATA=/home/alex/projects/lidar_tree_benchmarks/work/teak-validation-audit/sources \
  OUT=/home/alex/projects/lidar_tree_benchmarks/work/teak-validation-audit/replay-new
```

`SOURCE` contains the existing `neon/TEAK` field/result inventory and shared
NEON CSVs. `METADATA` must contain the archived `teak-site.json` and
`ept-resources.geojson`; public URLs and snapshot hashes are recorded in the
[source manifest](../docs/teak-validation-sources.json). Re-fetching a mutable
URL can change the snapshot. This local inventory cannot be reproduced from
a code checkout alone; it needs the recorded working inputs. Raw sources,
CSVs and receipts remain under `work/teak-validation-audit/`.

No new point clouds, annotations or model weights were downloaded, and no
inference, calibration fitting or scoring ran. README priorities, workflow
index and report links were updated. This audit does not reopen the
[retired eastern expansion](../docs/harv-bart-closeout.md).

The final offline replay verified 60 input/code hashes and 12 output hashes,
with 48 scanned CSV paths and 874 prediction/frozen artifact paths. Three
independent reviews covered scientific eligibility, primary sources and
reproducibility; confirmed provenance and terminology findings were fixed
and rechecked. Six focused assertions cover input mutation and path-list
changes. Existing-output and protected-input output guards also passed.

The full R suite passed. Three skips remain explicit: optional live FF3D
inference, an empty-LAS writer fixture limitation and unavailable Python
`plyfile`. A restricted-network R-universe package-index warning also occurred.
No Python/GPU implementation changed and no live model smoke was run.
Source byte counts/hashes, local links, repository-wide Markdown lint and
whitespace checks passed; the original checkout's 16 dirty paths were preserved.
