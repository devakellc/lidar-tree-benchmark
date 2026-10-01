# Pacific Northwest site extension preflight

Checked on 1 October 2026. This preflight decides whether NEON's two Domain 16
forest sites in Washington, Wind River Experimental Forest (WREF) and Abby Road
(ABBY), join the density ladder beside SJER, SOAP and TEAK. It is score-blind:
no detector was run and no plot was clipped for scoring.

**Decision: go for both sites.** Both were flown in July 2021 with the same
Optech Galaxy Prime instrument class as the D17 sites, at comparable native
density, and every admitted plot clip lies on listed tiles. **The reference
population is limited to stems of at least 10 cm DBH at every site**, because
seven ABBY distributed plots are young stands whose mapped stems are almost
all below 10 cm DBH and carry no NEON canopy position. Under that gate the two
sites add 63 plots and 1,863 core stems, and the five-site reference holds 106
plots and 2,525 stems.

## Acquisition and density

| Site | Forest | 2021 flight days | Frame | Header tile | Tile density, all / first returns per m² | Plot clips, all returns per m² | Plot clips, first returns per m² |
| --- | --- | --- | --- | --- | --- | --- | --- |
| WREF | Old-growth Douglas-fir and western hemlock | 18, 19, 23 and 24 July | UTM 10N, EPSG:32610 | 580000_5075000 | 18.7 / 9.8 | median 17.9, range 10.2–25.8 (9 tower plots) | median 9.8, range 5.3–15.2 |
| ABBY | Managed Douglas-fir | 19 and 24 July | UTM 10N, EPSG:32610 | 552000_5067000 | 16.3 / 10.1 | median 17.1, range 12.5–19.5 (7 tower plots) | median 9.6, range 7.0–11.0 |
| D17, for comparison | Sierra Nevada oak woodland to red fir | March or July 2021 | UTM 11N, EPSG:32611 | — | — | 16.3–19.2 across sites | 9.0–11.9 across sites |

- **Sensor.** NEON's 2021 L3 discrete-LiDAR processing report for each site
  states that it was "flown with Teledyne Optech Galaxy Prime 5060445 as part
  of payload P1C2" and lists the flight days above. The matching L1 reports
  carry a template sentence naming the ALTM Gemini, but their instrument
  folder is `Galaxy5060445`, so the L3 statement is taken as authoritative.
  Flight lines were flown at a 150 kHz pulse rate with an 18° scan angle.
- **Headers.** Both tiles are LAS 1.3, point format 3, created in September
  2021 and declaring EPSG:32610, which matches the field frame from the NEON
  location records. The system identifier and generating software name
  LAStools and `lascolor`, not the sensor.
- **Density units.** Tile density counts every point outside the noise
  classes over the fully flown 1 km² tile. Plot-clip density uses the sweep's
  own native clip (nominal core plus 25 m, height-normalised), the units that
  gate the ladder: all-return density sets the no-upsampling guard and
  first-return density the CHM resolution and smoothing branch. Every clip
  exceeds the 8 points/m² top rung in all-return density. First-return
  density falls below 8 at WREF_079 (7.6), WREF_085 (5.3) and ABBY_069 (7.0);
  those plots take the sub-8 smoothing branch at native density, as SOAP's
  sparsest plot (7.8) already does.
- Only tower plots lie wholly inside the two header tiles. Distributed-plot
  density will be measured when the ladder clips run.

## Field reference

Ground truth was built with `neon_ground_truth.R` at `YEAR=2021` and the
default four-year gap, from RELEASE-2026. All 1,509 WREF and 1,534 ABBY
mappable stems were geolocated from 183 and 167 named points. Two gates are
reported. **All mapped** is the sweep's historical gate: plots with at least
six live mapped trees, scored on stems inside the nominal core (tower ±20 m,
distributed ±10 m). **DBH ≥ 10 cm** drops stems below 10 cm DBH, or without a
DBH, before the same six-stem gate.

| Site | Gate | Plots admitted (tower / distributed) | Core stems | With NEON canopy position | Measured in 2021 |
| --- | --- | --- | --- | --- | --- |
| SJER | All mapped | 8 (7 / 1) | 71 | 52% | 0 |
| SOAP | All mapped | 18 (7 / 11) | 232 | 99% | 51 |
| TEAK | All mapped | 20 (7 / 13) | 396 | 97% | 193 |
| WREF | All mapped | 38 (20 / 18) | 1,081 | 98% | 548 |
| ABBY | All mapped | 32 (13 / 19) | 1,074 | 76% | 573 |
| SJER | DBH ≥ 10 cm | 6 (6 / 0) | 57 | 49% | 0 |
| SOAP | DBH ≥ 10 cm | 18 (7 / 11) | 231 | 99% | 51 |
| TEAK | DBH ≥ 10 cm | 19 (6 / 13) | 374 | 98% | 183 |
| WREF | DBH ≥ 10 cm | 38 (20 / 18) | 1,063 | 98% | 534 |
| ABBY | DBH ≥ 10 cm | 25 (13 / 12) | 800 | 99.5% | 550 |

The D17 all-mapped rows reproduce the historical sweep populations exactly,
which checks that the inventory applies the sweep's own gate. Across five
sites the reference grows from 46 plots and 699 core stems to 116 plots and
2,854 under the all-mapped gate, or from 43 and 662 to 106 and 2,525 under the
DBH floor.
The planning estimate of 1,148 WREF and 838 ABBY live mapped stems of at least
10 cm used API records through 2025; this RELEASE-2026 build, with records
through 2024, finds 1,129 and 836 and the same 38 and 25 plots.

WREF is understory-rich: its 1,081 core stems hold 546 codominant, 381
intermediate, 103 dominant and 28 suppressed trees, with 23 unclassified for
lack of a height. Intermediate trees are 35% of the WREF reference against
16% at SOAP. ABBY's DBH ≥ 10 cm reference is mostly codominant: 639
codominant, 88 intermediate, 68 dominant, 3 suppressed and 2 unclassified.

## ABBY young stands

Seven distributed plots, ABBY_002, 004, 005, 009, 011, 012 and 013, hold 237
core stems, and only one reaches 10 cm DBH. They are saplings and small trees
with a median recorded height of 3.5 m (range 1.7–9.8 m), 234 of them last
measured in 2019, and only one has a NEON canopy position.
`neon_ground_truth.R` therefore assigns their crown class from within-plot
height quantiles, which in a plot made only of saplings labels the tallest
4 m saplings "dominant". Across ABBY, 273 of the 1,074 all-mapped core stems
lack a DBH of at least 10 cm and 247 carry a height-quantile class. At D17
the corresponding counts are 26 of 699 and none.

Scoring these stems in the headline would mix a regeneration stratum into one
site only and corrupt its per-class recall. **The DBH ≥ 10 cm gate was
therefore adopted at every site on 1 October 2026**, with the all-mapped gate
kept as a sensitivity row and the seven young stands reported, if at all, as
a separate small-tree stratum. The cost at D17 is 37 stems and three plots,
two at SJER and one at TEAK. Keeping the all-mapped gate at D17 and flooring
only ABBY would have avoided that cost but mixed reference definitions across
sites. Historical D17 results keep their original 699-stem population.

No admitted plot shows a harvest signature in the census records. No core
stem at either site has a non-live record before the 2021 flight. Later
records mark 18 WREF and 70 ABBY core stems as no longer live, mostly ABBY
"No longer qualifies" entries in 2024 in the young stands, and only three as
removed.

## Census footprint and timing

Per-plot census records for the admitted plots list 800 m² of sampled tree
area in tower plots and 400 m² in distributed plots, as at D17; two ABBY
tower records list 400 m². Tower boxes cover 1,600 m², so full-box precision
remains a lower bound and the
[event-specific support audit](neon-reference-support-results.md) applies
unchanged.

Tower plots were censused almost every year at both sites. WREF distributed
plots were censused in 2019 and 2022, and ABBY distributed plots in 2017, 2019
and 2024, so their nearest measurement lies one to three years from the
flight. About half of the WREF and ABBY core stems were measured in 2021
(51% and 53%), against 49% at TEAK and 22% at SOAP. The ABBY plots measured
in 2019 are young, fast-growing stands, so their field heights will
under-state 2021 canopy height more than at the old-growth sites.

## Tile coverage and download

The archived RELEASE-2026 file list for July 2021 holds 264 WREF and 176 ABBY
classified 1 km tiles, with median sizes of 158 and 139 MB against 159 MB for
SOAP's July 2021 tiles. Under either gate, every admitted clip intersects
only listed tiles: 17 tiles at WREF and 20 at ABBY. Listing is not a physical
coverage audit, so the downloaded set was checked against those 37 tiles
below.

File identities are archived without signed URLs. NEON's cloud listings carry
CRC32C checksums and no MD5 for more than 99.7% of files, so the archive now
keeps CRC32C. The listings print CRC32C without leading zeros, so values are
zero-padded before comparison. `neon_download_lidar.R` then fetched 21 tiles
per site (3.6 GB at WREF and 3.1 GB at ABBY) over every plot with live mapped
trees. All 42 files match their listed size and CRC32C, every header declares
EPSG:32610, and all 37 tiles needed by admitted clips are present.

## Plot population handed to the freeze

Adopted DBH ≥ 10 cm gate, 38 WREF and 25 ABBY plots:

- WREF tower: 070–089 (all 20).
- WREF distributed: 001–005, 007, 009–020.
- ABBY tower: 061–065, 067–070, 073–076.
- ABBY distributed: 001, 003, 006, 008, 010, 014, 016, 017, 019, 023, 025,
  077.

The all-mapped sensitivity gate also admits seven ABBY plots: 002, 004, 005,
009, 011, 012 and 013. WREF_008, with five live mapped trees, fails both
gates. At D17 the adopted gate drops SJER_008, SJER_054 and TEAK_050.

## Limits

- One header tile per site; distributed-plot density is not yet measured.
- Nominal cores are not census support, and field-to-AOP positional accuracy
  is not audited beyond agreement of the declared frames.
- Crown classes come from field canopy position, not from the LiDAR; the
  height-quantile fallback is unreliable in single-cohort young stands.
- Field heights measured in 2019 at ABBY predate two growing seasons.

## Reproduction

```sh
export CLAUDE_JOB_DIR="$PWD/work"   # NEON_TOKEN set outside the repository
Rscript scripts/neon_ground_truth.R SITE=WREF YEAR=2021
Rscript scripts/neon_ground_truth.R SITE=ABBY YEAR=2021
Rscript scripts/preflight_site_extension.R SITES=WREF,ABBY YEAR=2021 \
  MONTH=2021-07 REFERENCE=SJER,SOAP,TEAK
Rscript scripts/neon_download_lidar.R SITE=WREF YEAR=2021
Rscript scripts/neon_download_lidar.R SITE=ABBY YEAR=2021
# Rerun to verify the downloaded tiles against the archived listing.
Rscript scripts/preflight_site_extension.R SITES=WREF,ABBY YEAR=2021 \
  MONTH=2021-07 REFERENCE=SJER,SOAP,TEAK
```

The preflight writes `site_summary.csv`, `plot_inventory.csv`,
`core_crown_class.csv`, `core_measurement_year.csv`, `released_listing.csv`,
`header_tiles.csv`, `header_plot_density.csv` and, once tiles exist,
`downloaded_tiles.csv` under `work/neon/site_extension_2021/`, with a contract
that binds them to the input and code checksums.
