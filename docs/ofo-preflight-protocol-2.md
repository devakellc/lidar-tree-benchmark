# Open Forest Observatory stem maps: second preflight protocol

Declared on 17 November 2026, after the
[first protocol](ofo-preflight-protocol.md) ended no-go for every plot group,
and before any of the new evidence below was computed. Like the first, this
preflight is score-blind: no detector under test is run on these plots and
nothing is scored. Its results go to
[the second preflight results](../results/ofo-preflight-2-results.md).

## Why a second protocol

The first protocol's registration was tested against NEON plots whose mapped
stem positions were taken as the truth. Both registration methods failed that
test. Several of the failed units, three Abby Road plots, a composite made
mostly of two of them, `SOAP_031` and `TEAK_046`, erred in the same direction
under two independent signals with tight stability. The method aligns stems
with their crowns. A test that takes mapped stem positions as the truth
cannot tell an error of the method from a real offset between a stem map and
its canopy, whether from georeferencing or from crowns displaced off their
stems. This protocol replaces that truth with one that does not rest on NEON
stem positions. It does not change the method.

The first protocol also cleared disturbance by comparing the catalogue's
drone canopy models with the 3DEP canopy. For groups A and B those missions
were flown after the 3DEP flights, so the check covered the wrong years. This
protocol replaces it for those groups with sources that cover the years
between survey and flight.

## What had been seen

When this protocol was declared, the following were known: the frozen
method's estimates and gate results on all 106 NEON plots and on every
catalogue plot with a cloud, including the plots of groups A and B; the
first protocol's flight, geometry, snow, leaf-off and drone results; and, for
14 annotated D17 plots, the number of annotated crowns and how much of each
core their image covers. No crown position had been compared with any stem.
Nothing about NIWO had been downloaded. No fire or treatment record had been
queried, and no canopy-presence check had been run.

## Scope

Groups A and B of the first protocol, with its plot screen, groups, flight,
geometry, frame, snow and leaf-off rules unchanged. Groups C and D keep the
first protocol's no-go. Outputs live under `<job>/ofo/preflight2`; the first
protocol's outputs are read, never rewritten, and nothing is written under
`<job>/neon`.

## The method

The registration method, its constants, its gate and its smallest stem
counts are those frozen in Amendment 1b of the first protocol (digest
`eede36eb4afc37a385dc3b204f0dcf660c29cc60bcf893293c8a546bb54803b6`). Group A
uses the height signal and group B the diameter signal, as before.

## Crown-frame truth

The truth for a NEON plot is the shift that moves its mapped stems onto
crowns drawn by people, not onto the LiDAR.

**Annotations.** The NeonTreeEvaluation benchmark (Weinstein and others,
2021) holds hand-drawn crown boxes on 0.1 m NEON camera images of 40 m
squares centred on NEON plots, with the canopy height model of the same
year. Files are taken from its public repository at one recorded commit, each
with its SHA-256. A plot is eligible when its annotation file is named
`<plot>_<year>.xml` and the plot is in the benchmark's `adopted` population
or is a NIWO plot below. Box pixels are converted to map coordinates with
the image's geotransform.

**Truth stems.** Live trees of at least 10 cm diameter, inside the image
shrunk by 2 m, that should be visible from above: NEON canopy position open
grown, full sun or partially shaded, or, where no position is recorded, a
height of at least 0.6 times the plot's tallest live tree. Other stems are
not used.

**Objective.** For a shift `s`, each truth stem scores
`exp(-d^2 / (2 sigma^2))` against every box and keeps its best score, where
`d` is the distance from the shifted stem to the box centre and `sigma` is
the larger of 0.5 m and a quarter of the box's mean half-side. The objective
is the sum over stems. Shifts run over ±12 m at 0.25 m steps. The truth is
the best shift, refined on each axis to the vertex of the parabola through
it and its neighbours by at most half a step; exact ties take the centre of
the tied shifts.

**Frame tie.** The camera image belongs to the annotation's flight year and
the method's surface may come from another flight. The annotation year's
canopy height model is correlated with the method's canopy surface for the
plot, over the image shrunk by 3 m, at shifts within ±3 m in 0.25 m steps,
with the same refinement. The truth is moved by that shift into the frame of
the method's surface.

**Credibility.** A plot's truth is credible when it has at least 8 truth
stems; its estimate is off the window's edge; the 90th percentile of the
distances from 200 bootstrap estimates (stems resampled with replacement,
seeds `seed_for("crowntruth", plot, NA, k)`) to the full estimate is at most
1.0 m; and the frame tie's peak correlation is at least 0.5 and off the
±3 m edge. Plots whose truth is not credible are left out of the test and
listed.

## Test units

- **Benchmark plots.** Annotated plots of the five benchmark sites. The
  method's estimates are the frozen variants' rows for single plots in the
  first protocol's development and confirmation tables; nothing is rerun.
  The method's surface is the plot's native 2021 frozen clip.
- **NIWO plots.** Niwot Ridge is a NEON subalpine conifer site that the
  benchmark has never used. Stems are built with `neon_ground_truth.R` at
  `YEAR=2020`, the site's flight nearest the benchmark's 2021 flights, and
  clips with the benchmark's frozen-clip provider, into a separate root
  under `<job>/ofo`. The frozen method is run once on each annotated plot,
  both signals, displaced by an offset drawn as in Amendment 1 with seed
  `seed_for("offset2", plot, NA)`. NIWO is used for this test only.

The method's crown-frame estimate for a unit is its estimated shift plus the
known offset. Its error is the distance from that estimate to the plot's
credible truth.

## Pass rule

Per signal, over the units with a credible truth, at least the frozen
smallest stem count and acceptance by the frozen gate: at least 10 units, a
median error of at most 1.0 m, and at least 90% of units within 2.0 m. These
are the accuracy limits of both earlier tests. A signal that passes is
admitted. If fewer than 10 units qualify, the test is inconclusive and the
signal is not admitted.

The benchmark and NIWO units are also reported apart, as are the distances
between each plot's mapped stems and its annotated crowns. The latter is
reported, not tested.

## Registering catalogue plots

A plot of group A or B is registered when its group's signal is admitted
and its estimate for that signal is accepted by the frozen gate at no fewer
than the smallest stem count, as before, and two further checks hold:

- **One clear peak.** The method's `second_peak` statistic, the best
  objective more than 3 m from the estimate relative to the best objective,
  both above the window's median, is at most 0.8. This guards against the
  repeated alignments of a planted grid.
- **Signals agree.** In group A, where the diameter signal is also accepted,
  the two estimates lie within 2.0 m of each other.

Registered positions, `pos_unc` and the reference schema follow the first
protocol.

## Disturbance between survey and flight

For groups A and B the interval runs from 1 January of the survey year to
the last flight day. A plot is cleared only when all three checks pass.
Snow and leaf-off are those of the first protocol.

- **Fire.** No fire perimeter in the interagency fire perimeter history
  (fire year within the interval's years) or the interagency perimeters of
  2016 onward (discovery date within the interval) intersects the plot
  polygon buffered by 50 m. Prescribed fires count.
- **Forest Service activities.** No completed activity in the Forest
  Service's timber harvest, hazardous fuel treatment or timber stand
  improvement records, with a completion or accomplishment date within the
  interval, intersects the plot polygon. These records cover National Forest
  land; elsewhere the check passes for lack of a record source, which is
  stated per plot.
- **Canopy over mapped trees.** At the registered positions, canopy remains
  over the plot's large live reference stems. In group A the test stems have
  a measured height of at least the larger of 10 m and the plot's median,
  and a stem counts as present when the 3DEP canopy maximum within 2 m is at
  least half its height. In group B the test stems have a diameter of at
  least 30 cm, and a stem counts as present when that maximum is at least
  5 m. The canopy is the method's surface for the plot. A plot passes when
  no more than 10% of at least 10 test stems are missing; with fewer than 10
  it is not checked and is held.

Every record queried is kept with its retrieval time and SHA-256.

## Decision

Per group, as in the first protocol: **go** when its signal is admitted, at
least three plots are admitted with at least 100 reference stems in their
headline cells, and licence handling is known; **hold** when it fails only
on checks that could not be made; **no-go** otherwise. A go group may have
its reference tables written. Freezing its clips and running detectors are
the next stages and are not part of this protocol. If the test of a group's
signal fails, that group is no-go, and this protocol allows no redesign.

## Limits stated in advance

- The truth rests on crown boxes drawn on camera images. Boxes merge or
  split crowns in dense canopy, and a box centre is not a treetop.
- Annotated benchmark plots are few and small, smaller than the catalogue
  plots, which makes the test harder for the method, not easier. The
  method's estimates on them were known before this protocol, though their
  truths were not.
- NIWO lies outside California and Oregon; it is used only to test the
  method.
- Fire and activity records miss events outside their coverage, and the
  canopy check sees the loss of large trees, not of small ones.
