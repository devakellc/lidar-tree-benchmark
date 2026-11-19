# Gated multichm: confirmation protocol

Written on 16 November 2026, before any of the runs it describes. It fixes
what is tested, on which data, and how each outcome is read, so that the
results can support or refute a stronger statement about `multichm_gated` than
the [calibration and validation study](../results/multichm-gated-results.md)
allows.

## The statement under test

"For airborne LiDAR at national-mapping densities, the gated variant is a
better default than `multichm`: it is better in closed-canopy conifer stands
and not worse elsewhere, at every density, and on acquisitions other than the
one it was calibrated on."

The calibration study cannot support this. Its features were chosen after
reading all 106 plots, its thresholds were calibrated on plots of both regions,
it covers one flight per site and one instrument for every closed plot, and it
was not run at the QL2 level.

## What is frozen

- The detector library and its constants as committed with the
  crown-spacing switch (`scripts/multichm_gated_lib.R`). A defect found during
  the confirmation is fixed only if the fix leaves every existing cell of the
  calibration study unchanged, and it is recorded in the results.
- Five configurations, named here and nowhere re-tuned:

| Name | Grid label | What it adds to the one above |
| --- | --- | --- |
| Stock | `stock` | `multichm` as in the paper runs |
| Floor | `z5_s0_c0_e0` | 5 m floor on deeper-layer peaks |
| Floor and exemption | `z5_s0_c0.6_e1` | Surface peaks skip the distance filter in closed stands |
| Declared | `z5_s0.75_c0.6_e1_d8` | First-return share gate where crowns are at least 8 m apart |
| Gate everywhere | `z5_s0.75_c0.6_e1` | The same gate in every closed stand |

- The scoring: the benchmark's population rules, greedy one-to-one matching
  within 4 m with the height gate, counts pooled by summing, the shift null of
  200 offsets and corrected F1 = (F1 − null F1) / (1 − null F1).
- Intervals: 95% percentile intervals of a paired bootstrap that resamples
  plots within site, 1,000 draws, the same draws for both configurations and
  for observed and null counts. They are not adjusted for the number of
  contrasts.

## What had been seen when this was written

- Everything in the calibration study, on the five density levels of the
  frozen 2021 clips (native and all-return targets of 8, 4, 2 and 1
  points/m²).
- A re-analysis of that study's cells made on the same day: a configuration
  selected on the California plots alone gains in Washington at every density
  level; the declared configuration changes nothing in California in F1 and
  lowers corrected recall there; in Washington it brings the detector level
  with CHM-VWF in corrected F1 at native density.
- Detection counts on four closed Douglas-fir plots outside the benchmark,
  which have no field reference.

No configuration other than stock had been run on any dataset of the
confirmation tests below.

## Reading a contrast

A contrast is one configuration minus another on one dataset and scope. Its
measure is the change in corrected F1 where the dataset has a shift null and
the change in F1 where it has none.

- **Better**: the interval lies above zero.
- **Not worse**: the interval's lower bound is at least −0.02.
- **Worse**: the interval lies below zero.
- **Inconclusive**: none of these.

A scope with fewer than 10 plots is reported and not read.

## Confirmation tests

These use data on which no gated configuration has been run.

| Test | Data | Scopes read | Primary contrast |
| --- | --- | --- | --- |
| C1. QL2 level | The frozen QL2 clips of the 106 plots (all-return target 3.2 points/m², about 2 pulses/m²) | Five sites, California, Washington, each site | Declared minus stock, five sites |
| C2. California native sparse flights | The 2017 and 2018 NEON flights (3.9 to 5.0 pulses/m² at the median) against the stems live in both epochs | The common plots pooled | Declared minus stock |
| C3. Washington flights of another year | One other released NEON flight per Washington site, chosen by the rule below, against the stems live in both epochs | Both sites pooled, each site | Declared minus stock, both sites |
| C4. 3DEP clouds | USGS 3DEP clouds over the benchmark plots, where a public tile set covers them, at their own density and thinned to 2 points/m² | Each region with at least 10 covered plots | Declared minus stock |
| C5. Complete labels | The ten FGI-EMIT development plots at native density and thinned to the NEON densities, scored against the manual tree labels, without a null | The ten plots pooled, per density | Declared minus stock in F1, with precision |

**Rule for C3.** For each of WREF and ABBY, the released discrete-return
flights other than July 2021 are listed with their instrument and the median
first-return density of the tiles the plot clips need. The flight chosen is the
one flown with an instrument other than the Optech Galaxy Prime that lies
closest in time to July 2021; if several lie equally close, the sparser; if
every flight used the Galaxy Prime, the sparsest. The choice is made from
listings, headers and processing reports only, before any detector is run on
that flight. The reference is the benchmark's stem population rebuilt for the
flight's year with the usual four-year gap, restricted to the stems live in
both epochs on plots adopted in both, as in the
[native sparse epoch study](../results/native-sparse-epoch-results.md).

**Secondary contrasts**, read on C1 and C3 and reported on every test:

- Declared minus floor and exemption: what the share gate adds.
- Floor and exemption minus floor: what the exemption adds.
- Floor minus stock: what the floor adds.
- Declared minus gate everywhere: what the crown-spacing switch adds.
- Declared minus CHM-VWF, where the baseline was run on the same clips.

On C3 and C4 the results also report how the stand measures transfer: canopy
cover, crown spacing and the first-return share of deeper-layer peaks beside
their 2021 values on the same plots, and the number of plots whose closed or
gated state differs.

## Checks on the data already used

These re-score or re-analyse the calibration study's cells. They are not
confirmation: the plots and clips are the ones the arm was built on.

- **R1. Selection with a region held out.** Select on the California plots at
  native density and score on the Washington plots at every level, and the
  reverse. The first had been seen when this protocol was written.
- **R2. Match radius of 2 m.** The five configurations re-scored at 2 m with a
  null at that radius, on every level.
- **R3. Scoring variants.** Optimal assignment, the crown-scaled tolerance,
  stems measured in the flight year only, and stem positions moved by their
  recorded uncertainty, at native density.
- **R4. Noise in the crown-spacing switch.** Crown spacing recomputed with the
  1 m grid shifted by 0.25, 0.5 and 0.75 m in each direction; the spread of a
  clip's spacing, the number of plots whose gated state changes, and the range
  of the declared configuration's pooled scores over the shifts. A gated plot
  takes the detections of gate everywhere and an ungated closed plot those of
  floor and exemption, so the scores are recomposed from existing cells.
- **R5. The peaks the gate removes.** Inside the censused subplots, the share
  of deeper-layer peaks matched to a census stem above the shift null, for the
  peaks the gate removes, the deeper-layer peaks it keeps and the surface
  peaks.
- **R6. Density routing.** The routing of the benchmark paper recomputed with
  the arm among the CPU and GPU candidates, its configuration selected on the
  California cells, at the six density levels.

## What each outcome allows

The statement under test is supported only if all of these hold for the
declared configuration against stock:

1. Better on C1 over the five sites and on C3 over both Washington sites.
2. Not worse, or better, in California on C1 and on C2.
3. Worse on no scope read in C1 to C5.
4. Better at the 2 m radius at native density over the five sites (R2).

If the declared configuration fails 1 or 3 and floor and exemption passes all
four, the statement is made for floor and exemption. If neither passes, no
general statement is made and the arm stays a post hoc result for closed
stands on the calibration flights.

**Which configuration is proposed.** A part is kept only if the new data
support it. The share gate is kept if declared minus floor and exemption is
better on C1 over the five sites or on C3 over both sites, and worse on
neither. Otherwise the proposal is floor and exemption. The exemption is kept
by the same rule against floor alone; otherwise the proposal is the floor.

C4 and C5 qualify the statement instead of deciding it. A worse outcome on C4
limits it to the NEON instruments, and a worse outcome on C5 to the forest
types of the benchmark. C4 or C5 may be left out if the data cannot be brought
into the scorer; the results then say so and the statement names what was not
tested.

## What the tests cannot show

- The plots of C1 to C3 are the plots the arm was built on. They test other
  densities, flights and instruments, not other stands. Only C4 on plots
  outside the calibration, C5 and field counts on stands outside the benchmark
  test other stands.
- The four outside Douglas-fir plots stay unvalidated until a field count of
  their trees is available.
- The learned detectors of the benchmark are used with published checkpoints
  and no calibration on these plots. A calibrated variant compared with them
  is not compared on equal terms, whatever these tests show.
