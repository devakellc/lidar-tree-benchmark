# Gated multichm: confirmation tests

Checked on 16 November 2026. These tests follow the
[confirmation protocol](../docs/multichm-gated-confirmation-protocol.md), which
was written before any of them was run. They ask whether `multichm_gated`, a
post hoc arm described in the
[calibration and validation study](multichm-gated-results.md), can be called a
better default than `multichm` beyond the flight it was calibrated on. The arm
is not one of the paper's twelve arms and the master tables do not include it.

**Outcome.** By the protocol's rules the statement is supported for the
declared configuration, at the margin. The arm is better than `multichm` at the
QL2 level on the five sites, with a clear interval. On a Washington flight of
another year and instrument it is better by an interval whose lower bound is
+0.0002, which other bootstrap draws put on either side of zero. It is not
worse in California on any dataset, and it is better at a 2 m match radius.

What the tests carry, part by part:

- **Closed conifer stands.** The gain holds at every density level from 9.8 to
  0.6 pulses/m², the QL2 level included, at 4 m and at 2 m, and under every
  matcher tried.
- **Open stands.** In California the arm is not worse and not better on every
  dataset, and it lowers recall there.
- **Another instrument.** About half of the calibration flight's gain carries
  over to the 2019 Washington flight (+0.023 against +0.040 on the same
  stems).
- **The share gate.** It adds corrected F1 at the QL2 level and nothing on the
  2019 flight, where it costs recall. Floor and exemption without it passes
  the same four conditions, with a stable interval on the 2019 flight.
- **The crown-spacing switch.** It adds nothing in corrected F1 on any new
  dataset. It raises plain F1 by keeping recall.
- **The floor.** Its gain carries over to the 2019 flight. Against complete
  labels it removes labelled small trees and is worse than `multichm`.
- **In the paper's density routing.** With its thresholds selected on
  California alone, the arm is the best Washington candidate below the QL2
  floor and level with ForestFormer3D in corrected F1 at every density, but
  the routing's California rule cannot tell it from `multichm`.
- **Not tested.** Closed stands on 3DEP instruments, for want of public tiles
  over the Washington plots, and any stand outside the benchmark with a field
  count.

## Configurations and reading

Five configurations were frozen by the protocol and none was re-tuned: stock
(`multichm`), floor (`z5_s0_c0_e0`), floor and exemption (`z5_s0_c0.6_e1`),
declared (`z5_s0.75_c0.6_e1_d8`) and gate everywhere (`z5_s0.75_c0.6_e1`). The
detector library was not changed during the tests.

A contrast is read on the change in corrected F1 where the dataset has a shift
null and on the change in F1 where it has none: better when the 95% interval
lies above zero, not worse when its lower bound is at least −0.02, worse when
it lies below zero, otherwise inconclusive. A scope with fewer than 10 plots is
not read. Intervals are paired plot-bootstrap percentiles, plots resampled
within site, 1,000 draws, not adjusted for the number of contrasts. "Corrected"
means corrected for chance agreement with the benchmark's 200 shifts per plot.

Each scorer first reproduced a published reference: the stock configuration
equals `lidRplugins::multichm` in every cell of every dataset, and where the
paper runs hold `multichm` detections and a shift null for the same clips, it
equals those too.

## C1. QL2 level

The frozen QL2 clips of the 106 plots (all-return target 3.2 points/m², about
2 pulses/m²). The plots are those of the calibration; the density level had
not been run with any gated configuration. At this level 62 plots are closed
and the share gate applies in 31.

Declared minus stock:

| Scope | Plots | Stems | Detections, declared / stock | F1, declared / stock | Corrected F1, declared / stock | Change in corrected F1 | Change in F1 | Reading |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Five sites | 106 | 2,525 | 3,152 / 3,149 | 0.480 / 0.449 | 0.195 / 0.169 | +0.025 [+0.012, +0.037] | +0.031 [+0.016, +0.044] | better |
| California | 43 | 662 | 877 / 948 | 0.434 / 0.432 | 0.244 / 0.238 | +0.006 [−0.007, +0.020] | +0.003 [−0.008, +0.012] | not worse |
| Washington | 63 | 1,863 | 2,275 / 2,201 | 0.497 / 0.456 | 0.172 / 0.137 | +0.035 [+0.019, +0.052] | +0.041 [+0.021, +0.060] | better |
| SJER | 6 | 57 | 152 / 178 | 0.328 / 0.325 | 0.198 / 0.198 | +0.001 [−0.036, +0.034] | +0.002 [−0.032, +0.030] | not read |
| SOAP | 18 | 231 | 358 / 379 | 0.445 / 0.441 | 0.249 / 0.241 | +0.008 [−0.007, +0.022] | +0.004 [−0.013, +0.017] | not worse |
| TEAK | 19 | 374 | 367 / 391 | 0.458 / 0.460 | 0.257 / 0.252 | +0.005 [−0.019, +0.030] | −0.002 [−0.017, +0.014] | not worse |
| WREF | 38 | 1,063 | 1,089 / 1,343 | 0.446 / 0.433 | 0.178 / 0.145 | +0.033 [+0.011, +0.057] | +0.013 [−0.012, +0.036] | better |
| ABBY | 25 | 800 | 1,186 / 858 | 0.550 / 0.491 | 0.161 / 0.124 | +0.037 [+0.011, +0.059] | +0.059 [+0.031, +0.085] | better |

What each part adds, as the change in corrected F1 and in F1:

| Part | Scope | Detections | Change in corrected F1 | Change in F1 | Change in corrected precision | Change in corrected recall | Reading |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Floor minus stock | Five sites | 2,897 / 3,149 | +0.004 [−0.001, +0.010] | +0.009 [+0.005, +0.014] | +0.011 [+0.006, +0.017] | −0.012 [−0.020, −0.006] | not worse |
| Floor and exemption minus floor | Five sites | 3,455 / 2,897 | +0.008 [+0.000, +0.016] | +0.019 [+0.009, +0.030] | −0.006 [−0.015, +0.002] | +0.045 [+0.025, +0.067] | better |
| Declared minus floor and exemption | Five sites | 3,152 / 3,455 | +0.013 [+0.005, +0.021] | +0.002 [−0.006, +0.010] | +0.018 [+0.010, +0.028] | −0.006 [−0.015, +0.003] | better |
| Declared minus gate everywhere | Five sites | 3,152 / 2,974 | +0.001 [−0.005, +0.007] | +0.010 [+0.004, +0.016] | −0.005 [−0.012, +0.000] | +0.016 [+0.006, +0.026] | not worse |
| Floor and exemption minus stock | Five sites | 3,455 / 3,149 | +0.012 [+0.003, +0.021] | +0.029 [+0.018, +0.040] | +0.005 [−0.005, +0.014] | +0.033 [+0.012, +0.054] | better |
| Declared minus floor and exemption | Washington | 2,275 / 2,566 | +0.015 [+0.004, +0.028] | +0.004 [−0.008, +0.016] | +0.022 [+0.012, +0.036] | −0.007 [−0.021, +0.006] | better |
| Declared minus floor and exemption | California | 877 / 889 | +0.003 [−0.001, +0.009] | −0.001 [−0.003, +0.000] | +0.003 [−0.000, +0.009] | +0.002 [−0.002, +0.008] | not worse |
| Declared minus CHM-VWF | Five sites | 3,152 / 1,463 | +0.026 [+0.000, +0.053] | +0.088 [+0.063, +0.116] | −0.086 [−0.117, −0.053] | +0.120 [+0.090, +0.154] | better |

- The declared configuration gains 0.025 [0.012, 0.037] in corrected F1 on
  the five sites and 0.035 [0.019, 0.052] in Washington. California does not
  move. No scope is worse.
- The share gate's own change is +0.013 [+0.005, +0.021] in corrected F1 and
  +0.002 [−0.006, +0.010] in F1. It comes from WREF (+0.027 [+0.011, +0.047]);
  at ABBY it is −0.002 [−0.011, +0.006].
- The exemption's own change in corrected F1, +0.008, has a lower bound of
  +0.0003, which is about the Monte Carlo error of a bound from 1,000 draws.
- The crown-spacing switch changes corrected F1 by +0.001 [−0.005, +0.007].
- CHM-VWF here is the paper's declared baseline, which smooths its canopy
  model below 8 pulses/m² and under-detects (see the
  [baseline smoothing sensitivity](baseline-smoothing-sensitivity-results.md)).
  Stock `multichm` is level with it in corrected F1 at this level (+0.001).

## C2. California native sparse flights

The 2017 flight at SJER and the 2018 flights at SOAP and TEAK of the
[native sparse epoch study](native-sparse-epoch-results.md), at 3.9 to 5.0
first returns per m² at the median, against the 586 stems live in both epochs
on 39 plots. Fifteen plots are closed on these flights, all with crowns at
least 8 m apart, so the declared configuration and gate everywhere place the
same detections.

| Contrast | Detections | Corrected F1 | Change in corrected F1 | Change in F1 | Change in precision | Change in recall | Reading |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Declared minus stock | 785 / 862 | 0.204 / 0.194 | +0.010 [−0.013, +0.034] | −0.009 [−0.027, +0.009] | +0.008 [−0.010, +0.025] | −0.046 [−0.076, −0.021] | not worse |
| Floor and exemption minus stock | 861 / 862 | 0.196 / 0.194 | +0.003 [−0.016, +0.021] | +0.004 [−0.010, +0.017] | +0.004 [−0.011, +0.017] | +0.005 [−0.015, +0.024] | not worse |
| Floor minus stock | 802 / 862 | 0.201 / 0.194 | +0.007 [−0.006, +0.019] | +0.006 [−0.004, +0.016] | +0.014 [+0.004, +0.025] | −0.015 [−0.027, −0.006] | not worse |
| Declared minus floor and exemption | 785 / 861 | 0.204 / 0.196 | +0.008 [−0.007, +0.025] | −0.013 [−0.027, −0.001] | +0.004 [−0.007, +0.016] | −0.051 [−0.072, −0.033] | not worse |

- The declared configuration is not worse in corrected F1. In plain F1 it is
  −0.009 [−0.027, +0.009], and recall falls by 0.046 [0.021, 0.076].
- The recall loss is the share gate's: against floor and exemption the
  declared configuration loses 0.051 [0.033, 0.072] recall and 0.013 [0.001,
  0.027] F1, with no change in precision.
- Canopy cover reads higher on the 2018 flights. Of the 35 SOAP and TEAK
  plots 15 count as closed, against 8 of the same 39 plots on the 2021
  clips; median cover is 0.11 higher at SOAP and 0.06 higher at TEAK. The
  gate therefore applies in more stands on the older, sparser instrument.
- On the 2021 clips of the same stems the declared configuration changes
  corrected F1 by +0.013 [+0.000, +0.027] at native density and by +0.000 and
  +0.006 at the two levels that bracket the sparse flights.

## C3. Washington flight of another year

**Choice of flight.** The protocol's rule was applied to listings, LAS headers
and NEON processing reports before any detector ran on the flights:

| Site | Flight | Instrument | All / first returns per m², needed tiles | Days from July 2021 | Outcome of the rule |
| --- | --- | --- | --- | --- | --- |
| WREF | June 2017 | Optech Gemini | 8.6 / 4.7 | 1,491 | Another instrument, farther in time |
| WREF | July 2018 | RIEGL Q780 | 30.9 / 10.4 | 1,105 | Another instrument, farther in time |
| WREF | July 2019 | RIEGL Q780 | 24.2 / 10.0 | 739 | Chosen |
| WREF | July 2022, June 2023 | Optech Galaxy Prime | 17.0 / 9.6, 17.3 / 9.5 | 356, 706 | Same instrument as 2021 |
| ABBY | June 2017 | Optech Gemini | 7.2 / 4.7 | 1,495 | Another instrument, farther in time |
| ABBY | July 2018 | RIEGL Q780 | 25.1 / 10.6 | 1,102 | Another instrument, farther in time |
| ABBY | July 2019 | RIEGL Q780 | 22.4 / 10.1 | 738 | Chosen |
| ABBY | July 2022, June 2023 | Optech Galaxy Prime | 16.3 / 10.0, 16.1 / 9.8 | 356, 708 | Same instrument as 2021 |

The 2025 flights exist only as provisional data and were left out. The 2019
flight is not sparser than 2021: it has about the same first-return density
and more returns per pulse (2.47 against 1.92 at WREF, 2.05 against 1.85 at
ABBY). The test is therefore one of another instrument and year, not of a
sparse acquisition. Twenty-nine tiles (6.0 GB) were downloaded and verified
against the listed sizes and checksums.

**Reference.** The stem population was rebuilt for 2019 and restricted to the
stems live in both epochs on plots adopted in both, with the 2021 rows on both
sides: 37 plots and 1,043 stems at WREF, 19 plots and 581 stems at ABBY. ABBY
loses six of its 25 plots: four lie on tiles the 2019 release does not list,
one sits on the flight edge with first returns over 39% of its core, and one
is adopted in 2021 only.

| Scope | Contrast | Plots | Stems | Detections | F1 | Corrected F1 | Change in corrected F1 | Change in F1 | Change in precision | Change in recall | Reading |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Both sites | Declared minus stock | 56 | 1,624 | 1,758 / 2,022 | 0.478 / 0.449 | 0.190 / 0.166 | +0.023 [+0.000, +0.045] | +0.030 [+0.002, +0.055] | +0.054 [+0.026, +0.081] | −0.011 [−0.065, +0.038] | better |
| Both sites | Floor and exemption minus stock | 56 | 1,624 | 2,141 / 2,022 | 0.489 / 0.449 | 0.187 / 0.166 | +0.021 [+0.005, +0.036] | +0.040 [+0.020, +0.059] | +0.028 [+0.009, +0.044] | +0.062 [+0.024, +0.100] | better |
| Both sites | Floor minus stock | 56 | 1,624 | 1,777 / 2,022 | 0.473 / 0.449 | 0.182 / 0.166 | +0.016 [+0.009, +0.023] | +0.024 [+0.020, +0.030] | +0.044 [+0.037, +0.053] | −0.010 [−0.017, −0.005] | better |
| Both sites | Floor and exemption minus floor | 56 | 1,624 | 2,141 / 1,777 | 0.489 / 0.473 | 0.187 / 0.182 | +0.005 [−0.010, +0.018] | +0.016 [−0.002, +0.033] | −0.016 [−0.036, −0.002] | +0.072 [+0.035, +0.111] | not worse |
| Both sites | Declared minus floor and exemption | 56 | 1,624 | 1,758 / 2,141 | 0.478 / 0.489 | 0.190 / 0.187 | +0.003 [−0.011, +0.017] | −0.011 [−0.025, +0.004] | +0.026 [+0.012, +0.045] | −0.073 [−0.103, −0.046] | not worse |
| Both sites | Declared minus gate everywhere | 56 | 1,624 | 1,758 / 1,581 | 0.478 / 0.454 | 0.190 / 0.187 | +0.003 [−0.012, +0.017] | +0.025 [+0.010, +0.040] | −0.001 [−0.014, +0.011] | +0.057 [+0.033, +0.079] | not worse |
| WREF | Declared minus stock | 37 | 1,043 | 874 / 1,275 | 0.457 / 0.453 | 0.197 / 0.176 | +0.021 [−0.005, +0.045] | +0.004 [−0.023, +0.029] | +0.081 [+0.052, +0.115] | −0.090 [−0.143, −0.043] | not worse |
| WREF | Declared minus floor and exemption | 37 | 1,043 | 874 / 1,219 | 0.457 / 0.468 | 0.197 / 0.189 | +0.008 [−0.016, +0.031] | −0.012 [−0.035, +0.009] | +0.059 [+0.029, +0.092] | −0.094 [−0.138, −0.058] | not worse |
| ABBY | Declared minus stock | 19 | 581 | 884 / 747 | 0.507 / 0.442 | 0.178 / 0.149 | +0.030 [−0.013, +0.068] | +0.065 [+0.011, +0.107] | +0.034 [−0.013, +0.073] | +0.131 [+0.025, +0.224] | not worse |
| ABBY | Declared minus floor and exemption | 19 | 581 | 884 / 922 | 0.507 / 0.520 | 0.178 / 0.183 | −0.005 [−0.020, +0.008] | −0.013 [−0.033, −0.000] | −0.005 [−0.015, +0.003] | −0.034 [−0.077, −0.006] | not worse |

The same stems on the 2021 clips, which are calibration data:

| Scope | Contrast | Detections | Change in corrected F1 | Change in F1 |
| --- | --- | --- | --- | --- |
| Both sites | Declared minus stock | 2,010 / 2,102 | +0.040 [+0.022, +0.058] | +0.035 [+0.014, +0.055] |
| Both sites | Floor and exemption minus stock | 2,365 / 2,102 | +0.024 [+0.009, +0.038] | +0.033 [+0.018, +0.047] |
| Both sites | Floor minus stock | 1,901 / 2,102 | +0.012 [+0.006, +0.017] | +0.020 [+0.015, +0.025] |
| Both sites | Declared minus floor and exemption | 2,010 / 2,365 | +0.016 [+0.005, +0.030] | +0.002 [−0.008, +0.013] |

- The declared configuration gains 0.023 in corrected F1 on the 2019 flight
  with an interval of [+0.0002, +0.0448]. The Monte Carlo error of such a
  bound is about 0.001. In 40 further sets of 1,000 draws, which the protocol
  did not ask for, the lower bound ran from −0.002 to +0.004 and was above
  zero in 33. The reading "better" therefore rests on the draw.
- Neither site alone separates from zero in corrected F1. At WREF the arm
  places 874 detections against 1,275: precision rises by 0.081 and recall
  falls by 0.090. At ABBY it places 884 against 747 and recall rises by
  0.131.
- The gain is about half of that on the 2021 clips of the same stems (+0.023
  against +0.040).
- The share gate does not carry over. Its own change is +0.003 [−0.011,
  +0.017] in corrected F1 and −0.011 [−0.025, +0.004] in F1, with recall
  0.073 lower, against +0.016 [+0.005, +0.030] on the 2021 clips.
- Floor and exemption gains 0.021 [0.005, 0.036] in corrected F1 and 0.040
  [0.020, 0.059] in F1. Its lower bound stayed above zero in all 40 further
  sets of draws (+0.003 to +0.006).
- The floor's own gain carries over: +0.016 [+0.009, +0.023].

**Stand measures on the other flight.** Canopy cover and crown spacing were
computed on both flights' clips of the 56 plots:

| Site | Plots | Median cover, 2019 / 2021 | Median crown spacing, 2019 / 2021 (m) | Closed, 2019 / 2021 | Closed and widely spaced, 2019 / 2021 | Plots whose state differs |
| --- | --- | --- | --- | --- | --- | --- |
| WREF | 37 | 0.915 / 0.906 | 8.45 / 8.38 | 37 / 37 | 24 / 22 | Two become gated (crown spacing 8.00 and 8.11 m against 7.83 and 7.98 m) |
| ABBY | 19 | 0.689 / 0.824 | 6.34 / 6.26 | 13 / 17 | 5 / 5 | Four are no longer closed (cover 0.50 to 0.59 against 0.63 to 0.74) |

Crown spacing transfers closely. Cover does not at ABBY, where the RIEGL
flight reads it 0.14 lower at the median, and it read higher on the older
California flights of C2. The 0.6 threshold therefore selects different
stands on different instruments.

## C4. 3DEP clouds

USGS 3DEP clouds were pulled over all 43 California plots: one tile set at
SJER (flown December 2019, 5.4 first returns per m² at the median) and one at
SOAP and TEAK (flown June to August 2022, 42 and 29 first returns per m²). No
public tile set covers a Washington plot, so the test has no closed-canopy
site of the benchmark's Washington kind. Eleven of the 43 plots are closed on
the 3DEP clouds at their own density, against 8 on the 2021 clips. The
reference is the 2021 stem population.

| Cloud | Contrast | Detections | Corrected F1 | Change in corrected F1 | Change in F1 | Change in precision | Change in recall | Reading |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Own density | Declared minus stock | 785 / 950 | 0.202 / 0.202 | +0.000 [−0.030, +0.029] | −0.019 [−0.048, +0.010] | +0.010 [−0.015, +0.034] | −0.082 [−0.111, −0.049] | inconclusive |
| Own density | Floor and exemption minus stock | 855 / 950 | 0.202 / 0.202 | +0.000 [−0.020, +0.022] | −0.001 [−0.020, +0.017] | +0.012 [−0.005, +0.031] | −0.035 [−0.051, −0.013] | inconclusive |
| Own density | Floor minus stock | 835 / 950 | 0.208 / 0.202 | +0.006 [−0.009, +0.021] | +0.004 [−0.008, +0.018] | +0.020 [+0.009, +0.034] | −0.035 [−0.048, −0.020] | not worse |
| Own density | Declared minus floor and exemption | 785 / 855 | 0.202 / 0.202 | +0.000 [−0.013, +0.013] | −0.017 [−0.033, −0.002] | −0.002 [−0.014, +0.008] | −0.047 [−0.069, −0.024] | not worse |
| Thinned to 2 points/m² | Declared minus stock | 891 / 958 | 0.223 / 0.209 | +0.014 [−0.000, +0.034] | +0.007 [−0.003, +0.020] | +0.017 [+0.007, +0.031] | −0.018 [−0.033, −0.003] | not worse |
| Thinned to 2 points/m² | Floor and exemption minus stock | 908 / 958 | 0.219 / 0.209 | +0.010 [−0.001, +0.025] | +0.009 [−0.000, +0.020] | +0.015 [+0.006, +0.026] | −0.009 [−0.021, +0.007] | not worse |
| Thinned to 2 points/m² | Declared minus floor and exemption | 891 / 908 | 0.223 / 0.219 | +0.004 [−0.001, +0.012] | −0.001 [−0.005, +0.002] | +0.002 [−0.000, +0.007] | −0.009 [−0.022, +0.000] | not worse |

- Thinned to 2 points/m² the declared configuration is not worse, +0.014
  [−0.000, +0.034].
- At the clouds' own density it changes corrected F1 by +0.000 with an
  interval that reaches −0.030, so the reading is inconclusive. Recall falls
  by 0.082 [0.049, 0.111] and F1 by 0.019 [−0.010, +0.048]. Against floor and
  exemption the share gate loses 0.017 [0.002, 0.033] F1.
- No scope is worse, so C4 does not limit the statement by the protocol's
  rule. It leaves closed stands on 3DEP instruments untested.

## C5. Complete labels

The ten FGI-EMIT development plots at native density and thinned to the NEON
densities, scored against the 841 manual tree labels with the apex matching of
the [FGI-EMIT thinning study](fgiemit-thinning-results.md). The labels are
complete, so precision is not a lower bound; there is no shift null, and the
measure is F1. Four plots are closed. The share gate applies in two of them at
native density and at 11.3 pulses/m², in one or none below.

| Pulses/m² | F1, stock | F1, floor | F1, floor and exemption | F1, declared | Declared minus stock | Floor minus stock | Floor and exemption minus floor | Reading, declared minus stock |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1,309 (native) | 0.550 | 0.532 | 0.538 | 0.533 | −0.016 [−0.029, +0.001] | −0.018 [−0.032, +0.002] | +0.006 [−0.003, +0.017] | inconclusive |
| 11.3 | 0.554 | 0.526 | 0.538 | 0.538 | −0.016 [−0.033, +0.006] | −0.028 [−0.038, −0.016] | +0.012 [−0.000, +0.024] | inconclusive |
| 5.4 | 0.534 | 0.527 | 0.552 | 0.550 | +0.016 [−0.007, +0.042] | −0.007 [−0.014, +0.002] | +0.025 [+0.000, +0.049] | not worse |
| 2.9 | 0.529 | 0.521 | 0.542 | 0.542 | +0.013 [−0.004, +0.030] | −0.008 [−0.019, +0.004] | +0.021 [−0.003, +0.044] | not worse |
| 1.5 | 0.523 | 0.506 | 0.539 | 0.538 | +0.015 [−0.016, +0.050] | −0.017 [−0.026, −0.004] | +0.032 [+0.001, +0.068] | not worse |
| 0.7 | 0.521 | 0.513 | 0.554 | 0.553 | +0.032 [−0.012, +0.078] | −0.007 [−0.010, −0.004] | +0.040 [−0.003, +0.086] | not worse |

- At native density and at 11.3 pulses/m², the density that corresponds to
  the NEON clips, the declared configuration scores 0.016 below `multichm`
  with intervals that reach below −0.02: inconclusive. Below that density it
  is not worse (+0.013 to +0.032, every interval including zero).
- The floor alone is worse than `multichm` at 11.3, 1.5 and 0.7 pulses/m²
  (−0.028 [−0.038, −0.016] at 11.3). At 11.3 pulses/m² it removes 44
  detections, about 30 of them matched to a labelled tree: recall falls by
  0.036 [0.027, 0.047] and precision does not move. On the NEON plots the
  floor costs nothing in corrected recall, because the reference there holds
  no stem under 10 cm DBH.
- From 5.4 pulses/m² down the exemption adds recall, +0.030 to +0.070, with
  precision 0.004 to 0.075 lower.
- The share gate changes F1 by −0.005 to +0.000.
- Floor and exemption minus stock is worse at 11.3 pulses/m² (−0.016 [−0.029,
  −0.003]). By the protocol a worse outcome on C5 limits a statement to the
  forest types of the benchmark.
- FGI-EMIT's clouds combine three scanners, each numbering its own returns,
  and the scanner of a return is not recorded in the development clouds. The
  first-return share there is a pooled quantity (0.46 to 0.91 for one
  scanner, 0.81 to 1.00 for the other two).

## Checks on the data already used

These re-score or re-analyse the calibration study's cells. The plots and
clips are those the arm was built on.

### R1. Selection with a region held out

| Selected on | Configuration selected | Level | Scored on | Change in corrected F1 against stock | Reading |
| --- | --- | --- | --- | --- | --- |
| California | `z5_s0.5_c0.6_e1` | 9.8 (native) | Washington, 63 plots | +0.037 [+0.018, +0.054] | better |
| California | `z5_s0.5_c0.6_e1` | 4.7 | Washington | +0.036 [+0.016, +0.054] | better |
| California | `z5_s0.5_c0.6_e1` | 2.5 | Washington | +0.043 [+0.025, +0.060] | better |
| California | `z5_s0.5_c0.6_e1` | 1.3 | Washington | +0.027 [+0.003, +0.049] | better |
| California | `z5_s0.5_c0.6_e1` | 0.6 | Washington | +0.045 [+0.022, +0.068] | better |
| Washington | `z5_s0.75_c0_e1_d8.5` | 9.8 (native) | California, 43 plots | −0.031 [−0.058, −0.006] | worse |
| Washington | `z5_s0.75_c0_e1_d8.5` | 4.7 | California | −0.021 [−0.044, +0.002] | inconclusive |
| Washington | `z5_s0.75_c0_e1_d8.5` | 2.5 | California | −0.022 [−0.046, −0.001] | worse |
| Washington | `z5_s0.75_c0_e1_d8.5` | 1.3 | California | −0.032 [−0.062, −0.000] | worse |
| Washington | `z5_s0.75_c0_e1_d8.5` | 0.6 | California | −0.051 [−0.078, −0.026] | worse |

- A configuration selected on the California plots alone is better than
  stock in Washington at every level. California cannot see the
  crown-spacing switch: every closed plot there has crowns at least 8 m apart,
  so the three variants with a switch tie with the selection on all 43 plots.
- The reverse fails. Washington holds two open plots, so its selection has no
  cover threshold, applies the rules in every stand, and is worse than stock
  in California. The protection of open stands rests on the cover threshold,
  which only the California plots identify.

### R2. Match radius of 2 m

Declared minus stock, with a null at 2 m:

| Pulses/m² | Five sites, change in corrected F1 | California | Washington | Five sites, change in F1 |
| --- | --- | --- | --- | --- |
| 9.8 (native) | +0.031 [+0.018, +0.043] | +0.003 [−0.005, +0.011] | +0.043 [+0.027, +0.060] | +0.046 [+0.032, +0.059] |
| 4.7 | +0.031 [+0.020, +0.043] | +0.006 [−0.003, +0.013] | +0.042 [+0.027, +0.059] | +0.048 [+0.032, +0.065] |
| 2.5 | +0.034 [+0.024, +0.044] | +0.005 [−0.005, +0.015] | +0.047 [+0.032, +0.063] | +0.051 [+0.036, +0.065] |
| 2.0 (QL2 level) | +0.033 [+0.021, +0.046] | +0.008 [−0.003, +0.019] | +0.044 [+0.025, +0.061] | +0.048 [+0.032, +0.066] |
| 1.3 | +0.021 [+0.008, +0.035] | −0.004 [−0.018, +0.007] | +0.032 [+0.014, +0.051] | +0.042 [+0.024, +0.061] |
| 0.6 | +0.024 [+0.012, +0.036] | −0.006 [−0.016, +0.002] | +0.036 [+0.020, +0.054] | +0.046 [+0.030, +0.063] |

The arm is better on the five sites and in Washington at every level and not
worse in California at any. The stock configuration at 2 m equals the paper
runs' 2 m null for `multichm` in every cell.

### R3. Scoring variants

Native density, all 106 plots, plain F1, declared minus stock:

| Scoring | Five sites | California | Washington |
| --- | --- | --- | --- |
| Baseline (greedy, 4 m) | +0.035 [+0.020, +0.049] | −0.001 [−0.017, +0.013] | +0.047 [+0.029, +0.066] |
| Optimal assignment | +0.045 [+0.027, +0.062] | −0.003 [−0.019, +0.011] | +0.062 [+0.040, +0.085] |
| Crown-scaled tolerance | +0.035 [+0.019, +0.050] | −0.002 [−0.018, +0.012] | +0.048 [+0.028, +0.067] |
| Optimal assignment, scaled | +0.045 [+0.026, +0.062] | −0.003 [−0.018, +0.012] | +0.062 [+0.040, +0.085] |
| Soft 3-D cost | +0.041 [+0.024, +0.058] | −0.008 [−0.022, +0.006] | +0.058 [+0.037, +0.081] |
| Greedy, 3 m | +0.041 [+0.026, +0.056] | −0.001 [−0.016, +0.011] | +0.056 [+0.037, +0.074] |
| Greedy, 5 m | +0.024 [+0.006, +0.040] | −0.002 [−0.018, +0.014] | +0.033 [+0.012, +0.054] |
| Stems measured in 2021 only (44 plots) | +0.059 [+0.040, +0.078] | +0.006 [−0.008, +0.021] | +0.069 [+0.048, +0.090] |
| Stem positions moved by their uncertainty, 5th to 95th percentile of 200 draws | +0.030 to +0.036 | −0.005 to +0.003 | +0.042 to +0.049 |

The gain does not depend on the matcher, the radius or the stem set, and
California stays at zero under each. In California the share gate costs F1
against floor and exemption under every matcher (−0.008 to −0.014, the
intervals excluding zero or ending on it), through recall. Under the soft
3-D cost the floor's own change in F1 is −0.004 [−0.009, +0.002]; under
every other matcher it is +0.011 to +0.017.

### R4. Noise in the crown-spacing switch

Crown spacing was recomputed with the 1 m grid at 16 placements (shifts of 0,
0.25, 0.5 and 0.75 m in each direction), and the declared configuration was
recomposed from existing cells: a gated plot takes the detections of gate
everywhere, any other plot those of floor and exemption. At the unshifted
placement this reproduces the declared cells in all 530 cells.

| Pulses/m² | Closed plots | Range of a closed plot's spacing over the placements: median / 90% / largest (m) | Closed plots changing gate state in at least one placement | Plots gated, least to most | Held-out change in corrected F1, five sites, least to most |
| --- | --- | --- | --- | --- | --- |
| 9.8 (native) | 69 | 0.44 / 0.80 / 1.16 | 8 | 36 to 39 | +0.034 to +0.035 |
| 4.7 | 63 | 0.42 / 0.68 / 1.54 | 6 | 31 to 34 | +0.026 to +0.032 |
| 2.5 | 62 | 0.40 / 0.76 / 1.38 | 8 | 28 to 31 | +0.034 to +0.040 |
| 1.3 | 62 | 0.47 / 0.92 / 1.15 | 8 | 28 to 32 | +0.014 to +0.017 |
| 0.6 | 62 | 0.54 / 0.80 / 1.47 | 13 | 27 to 34 | +0.018 to +0.024 |

A shift of a fraction of a metre moves a closed plot's crown spacing by 0.4 to
0.5 m at the median, and 8 of the 69 closed plots at native density change
gate state under some placement. The pooled scores hardly move. For one stand
near 8 m the switch is decided by where the grid falls, and across it the arm
keeps or drops most deeper-layer peaks.

### R5. The peaks the share gate removes

Inside the censused subplots of the 57 admitted plots at native density, the
detections of floor and exemption were labelled by what the gate would do to
them and scored once, so that no stem is claimed twice. "Above chance" is
(matched share − null share) / (1 − null share), with the null from the same
200 shifts.

| Scope | Plots | Surface peaks: count, above chance | Deeper peaks the gate keeps: count, above chance | Deeper peaks the gate removes: count, above chance |
| --- | --- | --- | --- | --- |
| All admitted plots | 57 | 645, +0.461 [+0.378, +0.553] | 45, +0.388 [+0.148, +0.635] | 243, +0.104 [+0.014, +0.212] |
| Plots where the declared configuration gates | 20 | 135, +0.516 [+0.392, +0.657] | 16, +0.240 [−0.130, +0.656] | 127, +0.059 [−0.029, +0.146] |
| Closed plots it does not gate | 25 | 426, +0.453 [+0.338, +0.593] | 19, +0.148 [−0.250, +0.648] | 92, −0.024 [−0.289, +0.205] |
| Open plots | 12 | 84, +0.376 [+0.218, +0.485] | 10, +0.832 [+0.454, +1.000] | 24, +0.575 [+0.388, +0.743] |
| Top height under 30 m | 16 | 252, +0.320 [+0.224, +0.487] | 13, +0.677 [+0.266, +1.000] | 23, +0.203 [−0.210, +0.451] |
| Top height 30 to 45 m | 27 | 304, +0.576 [+0.478, +0.667] | 23, +0.413 [+0.073, +0.764] | 133, +0.177 [+0.003, +0.349] |
| Top height 45 m and over | 14 | 89, +0.423 [+0.291, +0.575] | 9, −0.023 [−0.445, +0.442] | 87, −0.006 [−0.087, +0.069] |

- Where the declared configuration applies the gate, the peaks it removes
  match census stems no better than shifted peaks do (+0.059 [−0.029,
  +0.146]), against +0.516 for surface peaks. In stands of 45 m and over they
  are at chance (−0.006).
- In open plots the same kind of peak is a tree (+0.575 [+0.388, +0.743]),
  which is what the cover threshold protects.
- In stands 30 to 45 m tall the removed peaks are above chance (+0.177
  [+0.003, +0.349]), so some of them are trees.
- In closed plots the switch leaves ungated, the peaks it spares are at
  chance too (−0.024), with a wide interval: the null there is 0.63, so the
  measure has little room.
- The gate keeps 45 of the 288 deeper-layer peaks. In effect it drops the
  deeper layers where it applies.

### R6. Density routing with the arm as a candidate

The density routing of the benchmark paper sorts each cell, one plot at one
of six density levels, into a band of its measured first-return density: A at
8 pulses/m² or more, B from 2 to below 8, C below 2. In each band a route runs
the candidate with the highest pooled F1 on the California cells, among eight
detectors with a GPU or five classical ones without, and Washington is the
held-out check. It was recomputed with the arm as one more candidate in both
sets. Without the candidate the recomputation reproduces every pick, score,
interval and contrast of the paper's routing to 1e-9.

Two versions were run. In the first the candidate is `z5_s0.5_c0.6_e1`, the
configuration selected on the California plots alone (R1), so that Washington
stays held out from the selection of its thresholds, though not from the
design of the arm. In the second it is the declared configuration, whose
thresholds were calibrated on plots of both regions.

With the California-selected configuration:

| Band | Compute | Pick | Margin over the runner-up, California | Pick in Washington: F1 | Candidate in Washington: F1; corrected F1 | Pick minus candidate in Washington: F1; corrected F1 |
| --- | --- | --- | --- | --- | --- | --- |
| A | GPU | SegmentAnyTree | +0.008 [−0.028, +0.039] over ForestFormer3D | 0.512 | 0.496; 0.180 | +0.016 [−0.005, +0.036]; +0.029 [+0.005, +0.052] |
| A | CPU | The candidate | +0.005 [−0.010, +0.018] over `multichm` | 0.496 | — | — |
| B | GPU | ForestFormer3D | +0.000 [−0.019, +0.019] over the candidate | 0.489 | 0.500; 0.177 | −0.011 [−0.027, +0.007]; −0.008 [−0.027, +0.011] |
| B | CPU | The candidate | +0.001 [−0.006, +0.008] over `multichm` | 0.500 | — | — |
| C | GPU and CPU | `multichm` | +0.000 [−0.008, +0.011] over the candidate | 0.448 | 0.483; 0.171 | −0.035 [−0.056, −0.015]; −0.038 [−0.053, −0.024] |

The candidate run at every density, over all cells, against the routes and
the single detectors:

| Candidate minus | Five sites: F1 | Five sites: corrected F1 | Washington: F1 | Washington: corrected F1 | California: F1 | California: corrected F1 |
| --- | --- | --- | --- | --- | --- | --- |
| The paper's GPU route | +0.012 [+0.001, +0.025] | +0.007 [−0.003, +0.016] | +0.018 [+0.003, +0.033] | +0.017 [+0.006, +0.029] | −0.006 [−0.020, +0.009] | −0.012 [−0.028, +0.004] |
| ForestFormer3D | +0.013 [+0.002, +0.025] | +0.003 [−0.008, +0.015] | +0.013 [−0.002, +0.026] | +0.009 [−0.006, +0.023] | +0.010 [−0.005, +0.025] | −0.005 [−0.023, +0.013] |
| TreeisoNet | +0.026 [+0.014, +0.041] | +0.007 [−0.006, +0.021] | +0.008 [−0.005, +0.022] | −0.003 [−0.015, +0.010] | +0.060 [+0.033, +0.090] | +0.033 [+0.005, +0.061] |
| `multichm` | +0.028 [+0.014, +0.042] | +0.026 [+0.017, +0.035] | +0.037 [+0.019, +0.056] | +0.038 [+0.025, +0.049] | +0.001 [−0.006, +0.008] | +0.004 [−0.002, +0.011] |
| CHM-VWF | +0.073 [+0.051, +0.093] | +0.020 [+0.003, +0.037] | +0.076 [+0.052, +0.098] | +0.022 [+0.003, +0.039] | +0.064 [+0.027, +0.102] | +0.014 [−0.025, +0.053] |

By density level on the five sites, the candidate minus ForestFormer3D:

| Measure | 9.8 (native) | 4.7 | 2.5 | 2.0 (QL2 level) | 1.3 | 0.6 |
| --- | --- | --- | --- | --- | --- | --- |
| F1 | −0.016 [−0.032, +0.001] | −0.009 [−0.027, +0.007] | +0.015 [−0.001, +0.030] | +0.027 [+0.012, +0.041] | +0.026 [+0.011, +0.044] | +0.045 [+0.028, +0.062] |
| Corrected F1 | −0.007 [−0.027, +0.013] | −0.016 [−0.035, +0.003] | +0.005 [−0.014, +0.024] | +0.015 [−0.003, +0.033] | +0.002 [−0.017, +0.025] | +0.022 [+0.003, +0.041] |

- **The routing's rule cannot pick the arm out.** On the California cells the
  candidate is within 0.005 F1 of `multichm` in every band, every margin's
  interval including zero. The CPU route takes it in bands A and B and
  `multichm` in band C, each on a difference of 0.000 to 0.005. The GPU route
  does not change.
- **In Washington it is ahead of `multichm` in every band** (+0.035 to +0.042
  F1) and is the best candidate below the QL2 floor. Run at every density it
  is ahead of the paper's GPU route there by 0.018 [0.003, 0.033] F1 and
  0.017 [0.006, 0.029] corrected F1.
- **Against ForestFormer3D at every density** it is ahead by 0.013 [0.002,
  0.025] F1 on the five sites and level in corrected F1 (+0.003 [−0.008,
  +0.015]). By level it is level at native density and ahead in F1 from the
  QL2 level down; in corrected F1 it is level at every level but the
  sparsest.
- **The declared configuration** gives the same picture and is not held out.
  The CPU route takes it in band B only, `multichm` leading it by 0.001 on
  the California cells of band A. In Washington it is the best candidate in
  bands B and C for both routes, and the GPU route trails it by 0.026 [0.011,
  0.041] F1 over all cells.
- These rows set a detector calibrated on the benchmark's plots beside
  detectors run with published checkpoints and no calibration here. For the
  California-selected configuration only the choice of thresholds is blind to
  Washington.

## The protocol's decision

| Condition | Declared | Floor and exemption |
| --- | --- | --- |
| 1. Better on C1 over the five sites and on C3 over both Washington sites | Holds: +0.025 [+0.012, +0.037] and +0.023 [+0.000, +0.045] | Holds: +0.012 [+0.003, +0.021] and +0.021 [+0.005, +0.036] |
| 2. Not worse in California on C1 and on C2 | Holds: +0.006 [−0.007, +0.020] and +0.010 [−0.013, +0.034] | Holds: +0.003 [−0.010, +0.015] and +0.003 [−0.016, +0.021] |
| 3. Worse on no scope read in C1 to C5 | Holds | Fails on C5 at 11.3 pulses/m²: −0.016 [−0.029, −0.003] |
| 4. Better at 2 m at native density over the five sites | Holds: +0.031 [+0.018, +0.043] | Holds: +0.023 [+0.013, +0.034] |
| Share gate kept | Better on C1 (+0.013 [+0.005, +0.021]), not worse on C3 (+0.003 [−0.011, +0.017]) | — |
| Exemption kept | Better on C1 (+0.008 [+0.000, +0.016]), not worse on C3 (+0.005 [−0.010, +0.018]) | — |

By these rules the statement is supported for the declared configuration, and
the declared configuration is the one proposed. Two of the readings that
decide it rest on bounds at zero: the declared configuration on C3 (+0.0002)
and the exemption on C1 (+0.0003). The share gate's place rests on C1 alone,
which thins the calibration flight on the calibration plots; on the other
flight it adds nothing.

The protocol reads C4 and C5 as qualifications. C4 found nothing worse and
tested no closed Washington stand. On C5 the declared configuration is not
worse and is 0.016 below `multichm` at the two dense levels; floor and
exemption is worse at one.

Two places where the protocol's text allows two readings were handled by
reporting both: an interval wholly between −0.02 and zero is both worse and
not worse (it occurs once, for the floor on C5 at 0.7 pulses/m²), and
condition 3 names C1 to C5 while C4 and C5 are also said to qualify instead
of decide.

## What these tests do not show

- **Other stands.** C1 to C3 use the plots the arm was built on. They test
  other densities, another flight and another instrument, not other stands.
  C4 covers the California plots only, and C5 is a boreal forest scanned with
  three instruments at once.
- **One reference for both flights.** C3 scores both flights against the same
  stems, so an error in the reference is shared.
- **A sparse instrument in closed canopy.** The 2019 Washington flight is as
  dense as 2021. The older, sparser California flights hold 15 closed plots.
  No natively sparse flight over a closed Washington stand was scored.
- **Cover across instruments.** Cover reads 0.14 lower on the RIEGL flight at
  ABBY and higher on the older California flights. The arm's switch from open
  to closed rules is a threshold on that reading.
- **Stand-level stability.** Pooled scores are stable under grid shifts; a
  single stand near the 8 m threshold is not.
- **Small trees.** The NEON reference holds stems of at least 10 cm DBH. The
  floor's cost shows only against the complete labels of C5.
- **Stands outside the benchmark.** The four Douglas-fir plots that motivated
  the crown-spacing switch have no field count. In the benchmark's stands of
  their height, 30 to 45 m, some of the peaks the gate removes are trees.
- **Equal terms.** The arm's thresholds were calibrated on these plots. The
  learned detectors of the benchmark run with published checkpoints and no
  calibration here.

## A finding about another study

While reusing the clouds of the
[native QL2 cross-check](native-ql2-crosscheck-results.md), the 3DEP run found
that its cached clouds still hold the noise classes 7 and 18 and withheld
points, which that study's script and report say were dropped: at SOAP and
TEAK 4.7% and 4.8% of the cached points are withheld, up to 15% in one cloud.
The clouds of C4 were pulled afresh and do not hold them. The cross-check's
numbers were not recomputed here.

## Outputs

Under `work/multichm_gated_confirmation/`:

- `analysis/` holds `manifest.json` (the datasets and scopes read),
  `contrasts.csv` (every contrast of every dataset), `decision.csv`, the R1
  and R4 files and `tables.md`.
- `ql2/`, `tol2/`, `sparse_ca/`, `epoch_wa/` and `3dep/` hold each dataset's
  `cells.csv` in the calibration study's layout, with the record of its
  checks; `fgiemit/` the complete-label cells; `variants/` and
  `removed_peaks/` the R3 and R5 tables.
- `routing/california_selected/` and `routing/declared/` hold the R6 picks,
  scores and contrasts, and the check against the paper's routing.
- `protocol_stamp.txt` holds the time and hash of the protocol before the
  first run.

The 2019 Washington flight is under `work/epoch_wa_2019` (reference, tiles,
the sealed root and the stand measures), its 2021 side under
`work/epoch_wa_compare_2021`, and the record of the flight choice under
`work/epoch_wa_selection`.

## Reproduce

```sh
W=$PWD/work; C=$W/multichm_gated_confirmation; S=scripts/calval_multichm_gated.R
link() {  # link <job dir> <source of ground truth> <sites...>
  local job=$1 src=$2; shift 2
  for s in "$@"; do
    mkdir -p $job/neon/$s
    for f in ground_truth_stems.csv plot_centroids.csv; do
      ln -sfn $src/neon/$s/$f $job/neon/$s/$f
    done
  done
}
grid() {  # grid <out> <root> <sites> <rungs> [further arguments]
  local out=$1 root=$2 sites=$3 rungs=$4; shift 4
  for st in candidates score; do
    CLAUDE_JOB_DIR=$out/job Rscript $S STAGE=$st OUT=$out FROZEN_ROOT=$root \
      SITES=$sites RUNGS=$rungs CORES=9 "$@"
  done
}
FIVE=SJER,SOAP,TEAK,WREF,ABBY

# C1: the QL2 level, then its 2 m scores from the same candidates
link $C/ql2/job $W/paper_runs_ql2 SJER SOAP TEAK WREF ABBY
grid $C/ql2 $W/neon/frozen_2021_ql2 $FIVE 3.2 BASE=$W/paper_runs_ql2
CLAUDE_JOB_DIR=$C/ql2/job Rscript $S STAGE=score OUT=$C/ql2/tol2 TOL=2 \
  CANDIDATES=$C/ql2 FROZEN_ROOT=$W/neon/frozen_2021_ql2 RUNGS=3.2 \
  BASE=$W/paper_runs_ql2 CORES=9

# R2: 2 m on the calibration levels, from the study's candidates
link $C/tol2/job $W/paper_runs SJER SOAP TEAK WREF ABBY
CLAUDE_JOB_DIR=$C/tol2/job Rscript $S STAGE=score OUT=$C/tol2 TOL=2 \
  CANDIDATES=$W/multichm_gated_runs/neon/multichm_gated \
  FROZEN_ROOT=$W/neon/frozen_2021 BASE=$W/paper_runs CORES=9

# C2: the California native sparse flights and the same stems on 2021 clips
link $C/sparse_ca/sparse_2018/job $W/sparse_2018/compare_shared SOAP TEAK
grid $C/sparse_ca/sparse_2018 $W/sparse_2018/neon/frozen_2018 SOAP,TEAK native
link $C/sparse_ca/sparse_2017/job $W/sparse_2017/compare_shared SJER
grid $C/sparse_ca/sparse_2017 $W/sparse_2017/neon/frozen_2017 SJER native
link $C/sparse_ca/shared_2021/job $W/sparse_compare_2021/shared SJER SOAP TEAK
grid $C/sparse_ca/shared_2021 $W/neon/frozen_2021 SJER,SOAP,TEAK native,8,4
mkdir -p $C/sparse_ca/pooled
{ cat $C/sparse_ca/sparse_2018/cells.csv
  tail -n +2 $C/sparse_ca/sparse_2017/cells.csv; } > $C/sparse_ca/pooled/cells.csv

# C3: the 2019 Washington flight
J=$W/epoch_wa_2019; EP=WREF:$J:2019,ABBY:$J:2019
for s in WREF ABBY; do
  CLAUDE_JOB_DIR=$J Rscript scripts/neon_ground_truth.R SITE=$s YEAR=2019
done
CLAUDE_JOB_DIR=$J Rscript scripts/prepare_sparse_epoch.R \
  MONTHS=WREF:2019-07,ABBY:2019-07 MISSING_TILES=drop
CLAUDE_JOB_DIR=$J Rscript scripts/freeze_clips.R SITES=WREF,ABBY YEAR=2019 \
  CORES=4 OUT=$J/neon/frozen_2019
CLAUDE_JOB_DIR=$W Rscript scripts/compare_sparse_epoch.R MODE=prepare EPOCHS=$EP \
  C21=$W/epoch_wa_compare_2021 CLIPPED=TRUE MIN_CORE_COVER=0.95 STRATA=FALSE \
  POOLED=WA
CLAUDE_JOB_DIR=$W Rscript scripts/epoch_stand_measures.R EPOCHS=$EP \
  OUT=$J/stand_measures CORES=4
link $C/epoch_wa/epoch_2019/job $J/compare_shared WREF ABBY
grid $C/epoch_wa/epoch_2019 $J/neon/frozen_2019 WREF,ABBY native
link $C/epoch_wa/shared_2021/job $W/epoch_wa_compare_2021/shared WREF ABBY
grid $C/epoch_wa/shared_2021 $W/neon/frozen_2021 WREF,ABBY native

# C4, C5, R3 and R5
CLAUDE_JOB_DIR=$W Rscript scripts/confirm_gated_3dep.R STAGE=all CORES=6 HARNESS=ALL
Rscript scripts/confirm_gated_fgiemit.R CORES=6
A="BASE=$W/paper_runs CANDIDATES=$W/multichm_gated_runs/neon/multichm_gated"
A="$A FROZEN_ROOT=$W/neon/frozen_2021 CORES=4"
CLAUDE_JOB_DIR=$C Rscript scripts/confirm_gated_scoring_variants.R $A
CLAUDE_JOB_DIR=$C Rscript scripts/confirm_gated_removed_peaks.R $A \
  DECLARATION=docs/census-support-declaration-nearest.json \
  SUPPORT=$W/paper_runs/reference_support_census_event

# Contrasts, the decision, R1 and R4
CLAUDE_JOB_DIR=$W Rscript scripts/confirm_multichm_gated.R CORES=8

# R6: needs the routing library of the paper's density-routing study
L=/path/to/scripts/density_routing_lib.R
Rscript scripts/confirm_gated_routing.R ROUTING_LIB=$L CONFIG=z5_s0.5_c0.6_e1 \
  NAME=california_selected HELD_OUT=yes OUT=$C/routing/california_selected
Rscript scripts/confirm_gated_routing.R ROUTING_LIB=$L CONFIG=z5_s0.75_c0.6_e1_d8 \
  NAME=declared HELD_OUT=no OUT=$C/routing/declared
```

The last command reads `analysis/manifest.json`, which names each dataset's
cells file, test, levels and scopes. The NEON download of C3 needs
`NEON_TOKEN`; the tile sets of C4 are public. The grid of 447 configurations
is scored on every NEON dataset so that selections can be repeated, although
only the five frozen configurations are read here.
