# Native sparse epoch versus decimation

Checked on 1 October 2026. The density ladder simulates sparse acquisitions
by decimating the 2021 NEON clouds. The
[native 3DEP cross-check](native-ql2-crosscheck-results.md) could test that
only against a different, denser sensor thinned to the same target. This
study runs the same-sensor-family test: earlier NEON flights over the same
plots at their native sparse density, scored against the same field stems as
the 2021 clouds decimated to bracketing rungs. It also checks whether
published hand-drawn canopy boxes cover the scoring cores, which would give a
reference for precision that does not depend on the partial field census.

**Finding: decimation is slightly optimistic.** Against the 586 stems live in
both epochs on 39 common plots, the native sparse clouds (3.9 to 5.0 first
returns per m² at the median) give lower recall than the 2021 clouds
decimated to 8 or 4 points/m², which bracket that density: 0.03 to 0.05
lower for CHM-VWF and `multichm`, with 95% paired plot-bootstrap intervals
that exclude zero. F1 is 0.04 lower for CHM-VWF (interval excludes zero) and
0.02 lower for `multichm` (interval includes zero). For `multichm` the gap
sits in codominant and intermediate stems and dominant recall agrees; for
CHM-VWF it spans the dominant and codominant classes. Decimated rungs can
stand in
for native sparse acquisitions, with an optimism of a few points of recall
that the paper should state; the earlier cross-check found the same
direction (recall within 0.07).

The epochs are SJER 2017-03, SOAP 2018-06 and TEAK 2018-06. The
NeonTreeEvaluation boxes cover 14 tower cores and serve as a supplementary
visible-canopy reference. SegmentAnyTree has not been run on the sparse
clouds yet.

## Epochs

All NEON discrete-return LiDAR (DP1.30003.001) in RELEASE-2026. Tile sizes
are the median over a site's classified 1 km tiles and over the tiles that the
declared population's clips need (nominal core plus 25 m).

| Site | Month | Tiles | Median tile MB | Population tiles | Their median MB |
| --- | --- | ---: | ---: | ---: | ---: |
| SJER | 2017-03 | 118 | 25 | 11 | 33 |
| SJER | 2018-03 | 155 | 239 | — | — |
| SJER | 2019-03 | 132 | 30 | 11 | 35 |
| SJER | 2021-03 | 156 | 76 | 11 | 106 |
| SOAP | 2017-07 | 137 | 45 | 7 | 59 |
| SOAP | 2018-06 | 139 | 47 | 7 | 59 |
| SOAP | 2019-06 | 199 | 37 | 7 | 36 |
| SOAP | 2021-07 | 210 | 159 | 7 | 139 |
| TEAK | 2017-06 | 232 | 71 | 18 | 73 |
| TEAK | 2018-06 | 247 | 52 | 18 | 55 |
| TEAK | 2019-06 | 217 | 42 | 18 | 44 |
| TEAK | 2021-07 | 250 | 150 | 18 | 167 |

The 2013 flights predate every census and are omitted.

- **SJER 2018-03 is not sparse.** Its listing holds two classified tiles for
  many tile keys, a colorized and a plain one, plus flight-line clouds. One
  header tile over the tower plots holds 42.5 all and 28.9 first returns per
  m², three times the 2021 flight (13.7 / 8.8) on the same tile; 2017-03
  holds 6.1 / 5.2 and 2019-03 6.9 / 5.7.
- **SJER 2017-03** is one year after the 2016 census, which measured most
  SJER stems, and flies in March as in 2021. 2019-03 is equally sparse but
  holds only a small census.
- **SOAP and TEAK 2018-06** fly in June, a month earlier in the season than
  2021-07. The 2018 flight is the sparser of 2017 and 2018 at TEAK, and three
  years from the large 2015 tower census and one year from the 2019 bouts.

Every tile was checked against the archived release listing (size and
CRC32C) before use, and every header declares EPSG:32611. The listings are
archived without their signed download URLs.

## Native density

Plot clips come from the same frozen-clip provider as the 2021 ladder:
nominal core plus 25 m, single-threaded TIN normalization, a canonical point
order and hash-sealed roots, one per epoch. Densities are per clip; ranges in
brackets.

| Site | Epoch | Plots | All returns per m² | First returns per m² |
| --- | --- | ---: | --- | --- |
| SJER | 2017, tower | 17 | 6.7 (3.7–8.5) | 5.6 (2.8–6.9) |
| SJER | 2017, distributed | 9 | 6.0 (2.7–8.3) | 5.6 (2.7–6.3) |
| SJER | 2021 native, common plots | 20 | 14.8 (6.6–21.4) | 8.9 (4.2–13.2) |
| SJER | 2021 rung 8, common plots | 18 | 8.2 (6.9–8.6) | 5.7 (3.8–8.2) |
| SOAP | 2018, tower | 20 | 7.3 (4.9–12.0) | 5.0 (3.5–6.7) |
| SOAP | 2018, distributed | 14 | 9.0 (4.2–12.8) | 5.2 (3.6–7.0) |
| SOAP | 2021 native, common plots | 27 | 18.0 (9.9–22.0) | 12.5 (7.8–16.0) |
| SOAP | 2021 rung 8, common plots | 27 | 8.3 (8.1–8.7) | 6.1 (4.5–7.9) |
| TEAK | 2018, tower | 20 | 5.8 (3.7–8.3) | 3.7 (2.5–4.8) |
| TEAK | 2018, distributed | 17 | 5.0 (3.4–11.5) | 3.5 (2.2–6.5) |
| TEAK | 2021 native, common plots | 35 | 21.3 (12.7–29.4) | 12.6 (7.2–19.9) |
| TEAK | 2021 rung 8, common plots | 35 | 8.5 (8.0–8.8) | 5.5 (4.6–7.7) |
| TEAK | 2021 rung 4, common plots | 35 | 4.4 (4.2–4.6) | 2.9 (2.4–4.0) |

The sparse clouds hold 27% (TEAK), 45% (SOAP) and 60% (SJER) of the 2021
first-return density at the median. The ratio of all to first returns also
differs between epochs (1.2 at SJER in 2017 against 1.7 in 2021; about 1.5
at SOAP and TEAK against 1.4 and 1.7), so a rung chosen by all-return density
does not match first-return density. SJER and SOAP sit
close to the 2021 rung 8 in first returns; TEAK sits between rungs 4 and 8.

## Field reference

References were rebuilt for each epoch with the ground-truth builder at
`YEAR=2017` (SJER) and `YEAR=2018` (SOAP, TEAK) and the usual four-year gap,
in job directories separate from the 2021 data. The builder now drops mapped
stems in plots that have no plot-level record: 46 SOAP stems in SOAP_005,
011, 022 and 024 and one SJER stem in SJER_027, none of them measured or
live. The 2021 D17 references predate the check that rejected them.

The same population rules apply. A **2015-only** stem was last recorded in
2015 and never re-measured; the others were measured after 2015.

| Site | Epoch | Population | Plots | Core stems | 2015-only | Measured after 2015 | Plots also in the 2021 population |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| SJER | 2017 | adopted | 7 | 64 | 0 | 64 | 4 |
| SOAP | 2018 | adopted | 29 | 594 | 274 | 320 | 18 |
| TEAK | 2018 | adopted | 31 | 884 | 455 | 429 | 17 |
| SJER | 2017 | all mapped | 8 | 73 | 0 | 73 | 5 |
| SOAP | 2018 | all mapped | 29 | 597 | 275 | 322 | 18 |
| TEAK | 2018 | all mapped | 32 | 925 | 470 | 455 | 19 |

The sparse epochs reach many more tower plots than 2021 (SOAP 18 against 7,
TEAK 20 against 6), because the 2015 census measured whole tower plots and
the later bouts only subsets. Nearly half the SOAP and TEAK reference is
therefore 2015-only.

**Mortality bound for the 2015-only stratum.** Trees live in 2015 that have a
later record give an annualized mortality, fitted by maximum likelihood over
each tree's interval to its next record, with a 95% profile interval.

| Site | Trees | Dead at next record | Next records | Annual mortality | Expected dead by the flight |
| --- | ---: | ---: | --- | --- | --- |
| SOAP | 379 | 141 | 2019, 2021, 2023 | 6.1% (5.2–7.2%) | 17% (up to 20%) by 2018 |
| TEAK | 666 | 130 | 2021–2024 | 3.5% (2.9–4.1%) | 10% (up to 12%) by 2018 |
| SJER | 214 | 23 | 2016, 2024 | 10% (6.6–14%) | not needed; no 2015-only stems |

These rates span the 2012–2016 Sierra Nevada drought and bark-beetle
mortality. Re-measured trees lie in later sampled subplots, so the bound
assumes that mortality does not depend on subplot. Up to a fifth of the SOAP
2015-only stems and an eighth of the TEAK ones may be dead at the flight;
scored as live, they would understate recall by up to that share of the
stratum.

**The comparison reference.** Native sparse and decimated 2021 clouds should be
scored against the same stems. Of the adopted population, 586 stems are live
in both epochs' references on 39 plots present in both: 40 SJER stems on 4
plots, 209 SOAP stems on 18 and 337 TEAK stems on 17.

## Canopy reference

The NeonTreeEvaluation repository (Weinstein and others, 2021), at the
revision already pinned for the TEAK canopy package, holds 51 named D17 plot
annotations: 31 SJER and 18 TEAK images from 2018 and 2 SOAP images from 2019.
Each is a 400 by 400 pixel RGB image at 0.1 m, 40 m square, in EPSG:32611,
with hand-drawn boxes around visible crowns, standing dead included.

| Annotation | Core covered | Boxes in core | Core stems, adopted | Core stems, all mapped |
| --- | ---: | ---: | ---: | ---: |
| SJER_046_2018 | 99.8% | 14 | 6 | 6 |
| SJER_050_2018 | 99.0% | 15 | 22 | 22 |
| SJER_051_2018 | 99.8% | 13 | 6 | 8 |
| SJER_052_2018 | 99.7% | 9 | 8 | 8 |
| SJER_053_2018 | 99.9% | 11 | 9 | 9 |
| SJER_054_2018 | 99.7% | 10 | 0 | 6 |
| SOAP_031_2019 | 99.5% | 59 | 34 | 34 |
| TEAK_043_2018 | 94.4% | 23 | 16 | 22 |
| TEAK_044_2018 | 92.6% | 36 | 73 | 77 |
| TEAK_045_2018 | 91.7% | 37 | 30 | 30 |
| TEAK_046_2018 | 96.6% | 39 | 43 | 43 |
| TEAK_047_2018 | 99.2% | 36 | 32 | 34 |
| TEAK_050_2018 | 90.1% | 44 | 0 | 9 |
| TEAK_052_2018 | 99.9% | 73 | 12 | 12 |

Fourteen tower plots of the `adopted` or `all_mapped` population have an
image covering at least 90% of the 40 m scoring core, twelve of them in the
headline population. A further 13 SJER, 9 TEAK and 1 SOAP annotations cover
plots of the `relaxed` population only and were not downloaded. The boxes
record visible canopy whether or not NEON mapped the stem: TEAK_052 holds 73
boxes against 12 mapped stems, SOAP_031 59 against 34, while TEAK_044's 73
mapped stems include understory that no image shows (36 boxes).

The boxes can therefore give a canopy-level precision free of the census gap,
on 14 plots, as a supplement to the field-stem benchmark. The limits:

- Boxes, not crown outlines, apex heights or point labels.
- Imagery from 2018 (SJER, TEAK) and 2019 (SOAP): three and two years
  before the 2021 flights, across a period of high mortality; the same
  years as the sparse epochs at SOAP and TEAK, one year after SJER's.
- The [TEAK canopy package](teak-canopy-reference-results.md) found the
  paired LiDAR crops unusable (no CRS, inconsistent return fields); only the
  XML boxes and the RGB georeference are used here.
- Several learned arms may have seen NeonTreeEvaluation plots in training;
  exposure must be checked per checkpoint before any learned arm is scored
  against these boxes.

## Native sparse versus decimated 2021

CHM-VWF (`run_sweep.R`, density-derived CHM resolution, `a` = 0.10) and
`multichm` ran on each sealed root with the adopted population. To score both
sides on one reference, each arm ran again in job directories whose ground
truth holds only the comparison stems: for the shared stems, their 2021
records on both sides (same positions, heights and crown classes). The cores
coincide on every common plot. Pooled by summed counts, on the plots present
in all four compared cells.

| Arm | Site | Cell | Plots | Stems | First ret./m² | Recall | Precision | F1 | Overstory | Understory |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| CHM-VWF | SJER | sparse native | 4 | 40 | 4.2 | 0.53 | 0.35 | 0.42 | 0.67 | — |
| CHM-VWF | SJER | 2021 native | 4 | 40 | 8.3 | 0.62 | 0.27 | 0.38 | 0.86 | — |
| CHM-VWF | SJER | 2021 rung 8 | 4 | 40 | 5.1 | 0.53 | 0.34 | 0.41 | 0.67 | — |
| CHM-VWF | SJER | 2021 rung 4 | 4 | 40 | 2.9 | 0.55 | 0.33 | 0.41 | 0.71 | — |
| CHM-VWF | SOAP | sparse native | 18 | 209 | 5.0 | 0.29 | 0.35 | 0.32 | 0.34 | 0.07 |
| CHM-VWF | SOAP | 2021 native | 18 | 209 | 12.2 | 0.48 | 0.29 | 0.36 | 0.53 | 0.24 |
| CHM-VWF | SOAP | 2021 rung 8 | 18 | 209 | 5.6 | 0.32 | 0.41 | 0.36 | 0.37 | 0.10 |
| CHM-VWF | SOAP | 2021 rung 4 | 18 | 209 | 2.9 | 0.36 | 0.44 | 0.40 | 0.42 | 0.10 |
| CHM-VWF | TEAK | sparse native | 17 | 337 | 3.9 | 0.24 | 0.49 | 0.32 | 0.27 | 0.08 |
| CHM-VWF | TEAK | 2021 native | 17 | 337 | 11.7 | 0.37 | 0.42 | 0.39 | 0.40 | 0.15 |
| CHM-VWF | TEAK | 2021 rung 8 | 17 | 337 | 5.4 | 0.28 | 0.52 | 0.37 | 0.30 | 0.12 |
| CHM-VWF | TEAK | 2021 rung 4 | 17 | 337 | 2.8 | 0.27 | 0.47 | 0.34 | 0.29 | 0.08 |
| CHM-VWF | **D17** | sparse native | 39 | 586 | — | **0.28** | 0.41 | **0.33** | 0.31 | 0.09 |
| CHM-VWF | **D17** | 2021 native | 39 | 586 | — | 0.43 | 0.34 | 0.38 | 0.47 | 0.20 |
| CHM-VWF | **D17** | 2021 rung 8 | 39 | 586 | — | **0.31** | 0.45 | **0.37** | 0.34 | 0.12 |
| CHM-VWF | **D17** | 2021 rung 4 | 39 | 586 | — | **0.32** | 0.44 | **0.37** | 0.36 | 0.09 |
| `multichm` | SJER | sparse native | 4 | 40 | 4.2 | 0.72 | 0.25 | 0.37 | 0.81 | — |
| `multichm` | SJER | 2021 native | 4 | 40 | 8.3 | 0.78 | 0.26 | 0.39 | 0.86 | — |
| `multichm` | SJER | 2021 rung 8 | 4 | 40 | 5.1 | 0.70 | 0.22 | 0.33 | 0.86 | — |
| `multichm` | SJER | 2021 rung 4 | 4 | 40 | 2.9 | 0.78 | 0.24 | 0.36 | 0.90 | — |
| `multichm` | SOAP | sparse native | 18 | 209 | 5.0 | 0.57 | 0.28 | 0.37 | 0.62 | 0.36 |
| `multichm` | SOAP | 2021 native | 18 | 209 | 12.2 | 0.64 | 0.31 | 0.42 | 0.69 | 0.45 |
| `multichm` | SOAP | 2021 rung 8 | 18 | 209 | 5.6 | 0.65 | 0.31 | 0.42 | 0.70 | 0.45 |
| `multichm` | SOAP | 2021 rung 4 | 18 | 209 | 2.9 | 0.65 | 0.31 | 0.42 | 0.70 | 0.45 |
| `multichm` | TEAK | sparse native | 17 | 337 | 3.9 | 0.48 | 0.40 | 0.44 | 0.52 | 0.25 |
| `multichm` | TEAK | 2021 native | 17 | 337 | 11.7 | 0.50 | 0.41 | 0.45 | 0.54 | 0.29 |
| `multichm` | TEAK | 2021 rung 8 | 17 | 337 | 5.4 | 0.52 | 0.39 | 0.45 | 0.55 | 0.35 |
| `multichm` | TEAK | 2021 rung 4 | 17 | 337 | 2.8 | 0.50 | 0.38 | 0.44 | 0.54 | 0.23 |
| `multichm` | **D17** | sparse native | 39 | 586 | — | **0.53** | 0.32 | **0.40** | 0.57 | 0.31 |
| `multichm` | **D17** | 2021 native | 39 | 586 | — | 0.57 | 0.34 | 0.43 | 0.60 | 0.37 |
| `multichm` | **D17** | 2021 rung 8 | 39 | 586 | — | **0.58** | 0.33 | **0.42** | 0.61 | 0.41 |
| `multichm` | **D17** | 2021 rung 4 | 39 | 586 | — | **0.57** | 0.33 | **0.42** | 0.61 | 0.34 |

SJER has a single understory stem among the 40, so its understory column is
left blank. Densities are the median first-return density of the scored
clips. Recall by NEON crown class, D17 pooled (stems in brackets; 27 of the
586 stems carry no crown class):

| Arm | Cell | Dominant (154) | Codominant (314) | Intermediate (82) | Suppressed (9) |
| --- | --- | ---: | ---: | ---: | ---: |
| CHM-VWF | sparse native | 0.51 | 0.21 | 0.09 | 0.11 |
| CHM-VWF | 2021 native | 0.66 | 0.37 | 0.21 | 0.11 |
| CHM-VWF | 2021 rung 8 | 0.55 | 0.25 | 0.12 | 0.11 |
| CHM-VWF | 2021 rung 4 | 0.55 | 0.26 | 0.09 | 0.11 |
| `multichm` | sparse native | 0.73 | 0.49 | 0.28 | 0.56 |
| `multichm` | 2021 native | 0.71 | 0.55 | 0.37 | 0.44 |
| `multichm` | 2021 rung 8 | 0.71 | 0.57 | 0.41 | 0.33 |
| `multichm` | 2021 rung 4 | 0.72 | 0.56 | 0.30 | 0.67 |

Sparse native minus each 2021 cell, D17 shared stems, with 95% intervals
from 2,000 paired bootstrap resamples of plots within site:

| Arm | Versus | Recall | Precision | F1 |
| --- | --- | --- | --- | --- |
| CHM-VWF | 2021 rung 8 | −0.032 (−0.066 to −0.007) | −0.041 (−0.082 to −0.003) | −0.036 (−0.069 to −0.009) |
| CHM-VWF | 2021 rung 4 | −0.039 (−0.072 to −0.009) | −0.030 (−0.078 to +0.012) | −0.037 (−0.071 to −0.004) |
| CHM-VWF | 2021 native | −0.147 (−0.199 to −0.102) | +0.070 (+0.021 to +0.113) | −0.045 (−0.094 to −0.001) |
| `multichm` | 2021 rung 8 | −0.048 (−0.084 to −0.012) | −0.007 (−0.035 to +0.018) | −0.018 (−0.048 to +0.010) |
| `multichm` | 2021 rung 4 | −0.041 (−0.080 to −0.005) | −0.010 (−0.040 to +0.016) | −0.020 (−0.050 to +0.009) |
| `multichm` | 2021 native | −0.039 (−0.072 to −0.006) | −0.020 (−0.053 to +0.009) | −0.026 (−0.059 to +0.003) |

**Reading.** Both bracketing rungs give higher recall than the native
sparse flight, so decimating to a matched density would too: the native
sparse acquisition finds fewer stems than its decimated stand-in, by 3 to 5
points, most of them codominant. SOAP and TEAK carry the gap; on SJER's four
plots the cells differ by at most three of 40 stems. Precision moves less
and, for `multichm`, not detectably. The comparison mixes a sensor change
with a canopy change:
the shared stems were live at both epochs, but neighbours died or grew in
three years of drought mortality, and the 2018 SOAP and TEAK flights are in
June rather than July. It is evidence that decimation is mildly optimistic,
not a calibrated correction.

### The 2015-only stratum

Kept out of the shared comparison and scored separately. Those stems have
no height (the 2015 census measured DBH only), so the matcher pairs them on
position alone, without the height-consistency gate. To compare like with
like, the re-measured stratum is also scored with its heights removed.
Native sparse clouds, every adopted plot of the sparse references:

| Arm | Stratum | Plots | Stems | Recall | Overstory | Understory |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| CHM-VWF | 2015-only | 34 | 729 | 0.29 | 0.36 | 0.23 |
| CHM-VWF | re-measured, no height | 54 | 749 | 0.32 | 0.37 | 0.23 |
| CHM-VWF | re-measured, with height | 54 | 749 | 0.29 | 0.34 | 0.20 |
| `multichm` | 2015-only | 34 | 729 | 0.61 | 0.65 | 0.57 |
| `multichm` | re-measured, no height | 54 | 749 | 0.62 | 0.66 | 0.56 |
| `multichm` | re-measured, with height | 54 | 749 | 0.56 | 0.58 | 0.50 |

The 2015-only stems are found as often as re-measured stems scored the same
way, within 0.03, well inside the 10–20% dead fraction the mortality bound
allows. The two strata lie partly on different plots (2015-only stems are
almost all in tower plots), so this is a consistency check, not a mortality
estimate. Dropping the height gate alone adds 0.03 (CHM-VWF) to 0.06
(`multichm`) recall, so 2015-only results must never be pooled with
height-gated ones. On the nine common plots that hold 2015-only stems (94
stems) the 2021 clouds recall them about as well as the sparse ones; with so
few stems this says nothing about their survival.

### SegmentAnyTree

Not run yet; it needs the GPU. The commands below write into the same
comparison job directories, and the report picks the results up:

```sh
W=$(pwd)/work
for S in SOAP TEAK; do
  CLAUDE_JOB_DIR=$W/sparse_2018/compare_shared Rscript scripts/detect_segmentanytree_sweep.R \
    SITE=$S POP=adopted FROZEN_ROOT=$W/sparse_2018/neon/frozen_2018 RUNGS=native CORES=2
  CLAUDE_JOB_DIR=$W/sparse_compare_2021/shared Rscript scripts/detect_segmentanytree_sweep.R \
    SITE=$S POP=adopted FROZEN_ROOT=$W/neon/frozen_2021 RUNGS=native,8,4 CORES=2
done
CLAUDE_JOB_DIR=$W/sparse_2017/compare_shared Rscript scripts/detect_segmentanytree_sweep.R \
  SITE=SJER POP=adopted FROZEN_ROOT=$W/sparse_2017/neon/frozen_2017 RUNGS=native CORES=2
CLAUDE_JOB_DIR=$W/sparse_compare_2021/shared Rscript scripts/detect_segmentanytree_sweep.R \
  SITE=SJER POP=adopted FROZEN_ROOT=$W/neon/frozen_2021 RUNGS=native,8,4 CORES=2
```

## Reproduce

```sh
W=$(pwd)/work
for J in sparse_2018:SOAP:2018 sparse_2018:TEAK:2018 sparse_2017:SJER:2017; do
  IFS=: read D S Y <<< "$J"
  CLAUDE_JOB_DIR=$W/$D Rscript scripts/neon_ground_truth.R SITE=$S YEAR=$Y
done
CLAUDE_JOB_DIR=$W/sparse_2018 Rscript scripts/prepare_sparse_epoch.R \
  MONTHS=SOAP:2018-06,TEAK:2018-06
CLAUDE_JOB_DIR=$W/sparse_2017 Rscript scripts/prepare_sparse_epoch.R MONTHS=SJER:2017-03
CLAUDE_JOB_DIR=$W/sparse_2018 Rscript scripts/freeze_clips.R SITES=SOAP,TEAK YEAR=2018 \
  CORES=4 OUT=$W/sparse_2018/neon/frozen_2018
CLAUDE_JOB_DIR=$W/sparse_2017 Rscript scripts/freeze_clips.R SITES=SJER YEAR=2017 \
  CORES=4 OUT=$W/sparse_2017/neon/frozen_2017
EP=SJER:$W/sparse_2017:2017,SOAP:$W/sparse_2018:2018,TEAK:$W/sparse_2018:2018
CLAUDE_JOB_DIR=$W Rscript scripts/audit_sparse_epoch.R EPOCHS=$EP OUT=$W/sparse_2018/audit
CLAUDE_JOB_DIR=$W Rscript scripts/compare_sparse_epoch.R MODE=prepare EPOCHS=$EP \
  C21=$W/sparse_compare_2021
# then, in every comparison job directory J with its root R (the sparse root,
# or $W/neon/frozen_2021 for the directories under sparse_compare_2021):
#   CLAUDE_JOB_DIR=$J Rscript scripts/run_sweep.R SITE=$S POP=adopted \
#     FROZEN_ROOT=$R CORES=8 TOL=4 OUT=$J/neon/$S/sweep.csv
#   CLAUDE_JOB_DIR=$J Rscript scripts/detect_multichm_sweep.R SITE=$S POP=adopted \
#     FROZEN_ROOT=$R CORES=8 TOL=4 OUT=$J/neon/$S/multichm.csv
CLAUDE_JOB_DIR=$W Rscript scripts/compare_sparse_epoch.R MODE=report EPOCHS=$EP \
  C21=$W/sparse_compare_2021 OUT=$W/sparse_2018/compare_report
```

The comparison job directories are `compare_shared`, `compare_2015only`,
`strata_2015only`, `strata_remeasured` and `strata_remeasured_noheight`
under each sparse job directory, and `shared` and `only2015` under
`sparse_compare_2021`. The ground-truth builder reuses a site's cached
woody-vegetation download when it is copied into the job directory's `vst/`
folder.

## Caveats and open questions

- **Bracketing, not matching.** The 2021 side uses the canonical rungs 8
  and 4, which straddle the sparse first-return density. The ladder thins
  all returns uniformly, while a sparser sensor drops pulses. A per-plot
  pulse-thinned rung (lidR `homogenize` with `use_pulse`) at the sparse
  first-return density would sharpen the comparison.
- **Season and canopy change.** SOAP and TEAK fly in June in 2018 and July
  in 2021; SJER in March both times. Three years of growth and drought
  mortality lie between the epochs.
- **Small SJER sample.** Four common plots and 40 stems; SJER contributes
  little to the pooled result.
- **No decimation-noise band here.** The decimation noise of a pooled D17
  metric is about 0.01 (frozen-clip study); the bootstrap intervals, which
  resample plots, are wider and dominate.
- **The 2015-only stratum** stays out of every headline comparison.
