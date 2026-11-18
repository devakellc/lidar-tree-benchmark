# Chance-Correction Simulation

Checked on 17 November 2026. This study is post hoc: it was added after an
internal review of the paper, after all benchmark results were known, and it
was extended twice the same day, each time after a review of the version
before. The first version simulated one stand structure, an unclustered one
(random beyond a 1.5 m minimum spacing) with every tree mapped, and its
headline, that the corrected scores are conservative, followed from that
design. The first extension (scenario 4) varies the stand structure and the
completeness of the reference, adds detectors without skill whose detections
follow the trees, and measures how clustered the benchmark's own reference
stems are. It found the level of the corrected scores biased either way, but
its leads still looked conservative: every simulated leader differed from the
baseline only by more detections of its own trees or by more uniform
commission, and against those the corrected F1 leads stayed below the leads
of an oracle score in every setting, and extra commission alone never gave a
positive corrected F1 lead. The second extension tests those two statements
with a detector whose extra detections follow the trees without finding the
mapped stems, the baseline with split crowns (comparison (d)), and with a
paired comparison of two detectors without skill (comparison (e)); it also
adds a density-free measure of clustering, the excess of neighbours. Both
statements turn out to hold for uniform commission only. The study asks how
the paper's chance-corrected scores behave when the truth is known. The
scoring and the null are the benchmark's own code, unchanged; only the plots
and the detectors are synthetic.

The paper's [chance-agreement
null](matcher-robustness-results.md#chance-agreement) scores a cell's detections
after a random toroidal shift, and corrected F1 is (F1 − null F1) / (1 − null
F1). Its argument for recall: if a share s of stems is found by skill and the
rest can match only by chance, recall = s + (1 − s) × null, so s = (recall −
null) / (1 − null). Here s is known, and the question is how close the corrected
scores come to it.

## Findings

The corrected scores measure how much closer the detections lie to the mapped
stems than shifted copies of the same detections. They are not an unbiased
estimate of the share of stems a detector finds, and their leads are not
bounds on a difference in skill:

- In the unclustered stand, corrected recall falls short of the true skilled
  share in every setting, by 0.06–0.14 at 4 m and 0.02–0.07 at 2 m, whether or
  not trees are left out of the reference (Tables 1 and 6).
- In loosely clustered stands it falls short by about 0.07 at 4 m when every
  tree is mapped, and by less as the reference thins, down to about zero when
  a random 60% of the trees at 240 trees/ha are mapped (Table 6).
- In tightly clustered stands it is close to the truth at 4 m when every tree
  is mapped, and it exceeds the truth once detectable trees are left out of
  the reference: by 0.04–0.06 with 80% of the trees mapped and 0.08–0.13 with
  60% at 4 m, and by 0.04–0.08 at 2 m (Table 6).
- Detections that lie beside the mapped stems rather than on them score above
  zero in clustered stands without any skill: placed 5–10 m from their trees,
  they reach a corrected recall of +0.11 to +0.15 at 4 m and lead a uniform
  detector without skill by +0.06 to +0.10 in corrected F1 (Tables 7 and 8).

With extra skill on a detector's own trees, or with extra uniform commission,
corrected F1 leads behave as intended: more skill gives a positive lead and
more commission a negative one in every setting, and both stay below the leads
of an oracle score that counts only a stem's own detection (Tables 2 and 7).
Extra detections that follow the trees without finding the mapped stems
reverse that ordering: split crowns, which add no skill, lift the corrected F1
lead above the oracle lead in every setting and above zero in the tight
clusters (up to +0.06 at 4 m), though not in the loose clusters at about the
benchmark's segmenters' surplus of detections, and they raise corrected
recall by up to +0.13 in the loose clusters and +0.19 in the tight ones
(Tables 7 and 9). A corrected recall lead is therefore not by itself evidence
of skill. Where half of each core holds no reference, an F1 lead falls to
about half or less, observed, corrected and in the oracle alike (Tables 2 and
9). The benchmark's reference stems, on the distributed plots where the
mapped area is known, are about as clustered as the loose clusters (Table
10). Whether the benchmark's corrected scores and leads understate or
overstate skill is not established. A later
[split-crown diagnostic](split-crown-diagnostic-results.md) counts such
detections in the benchmark: the segmenters place them at about half the rate
simulated here or less, enough for part of their corrected recall lead.

**(i) Whether corrected recall falls short of the true skilled share or
exceeds it depends on stand structure and reference completeness** (Tables 1
and 6). In the unclustered stand of scenarios 1 to 3 it is below the truth in
every setting: at 4 m it recovers 61–89% of the truth (0.06–0.14 below it),
at 2 m 86–92% (0.02–0.05 below). The cause is the correction's assumption
that a stem the detector truly missed matches at the null's rate. In this
stand the detections near reference stems are taken by their own stems, so
the missed stems find fewer chance partners than the shifted copies offer: at
4 m the missed stems are matched 0.03–0.17 less often than the null recall, at
2 m 0.01–0.07 less often. With 80% or 60% of its trees mapped, the unclustered
stand stays below the truth, by 0.06–0.14 at 4 m and 0.03–0.07 at 2 m for
the baseline and the skilled detector: its unmapped trees stand no closer to
the mapped ones than at random, so their detections act like uniform
commission. In the tight clusters with every tree mapped, corrected recall is
close to the truth at 4 m (−0.007 [−0.016, +0.004] for the baseline, −0.015
[−0.023, −0.005] for the skilled detector) and above it at 2 m (+0.019 and
+0.015). With 80% of the trees mapped it is above the truth by 0.037–0.059 at
4 m and 0.037–0.055 at 2 m; with 60% mapped by 0.075–0.131 and 0.065–0.084,
whether the total or the reference density is held. In the loose clusters it
is below the truth by about 0.07 at 4 m with every tree mapped and by 0.03
with 80% mapped, and about level with it with 60% mapped at 240 trees/ha
(+0.013 [−0.006, +0.031] and +0.005 [−0.009, +0.020]); holding the reference
density instead keeps it below (by 0.018–0.048). These loose-cluster ranges
hold when the trees left out of the reference are a random share of the
stand, as simulated. The missed stems show the mechanism. A detection that
lies beside a reference stem rather than on it, whether of a neighbouring
tree, mapped or not, or of no tree, can match the stem when the stem's own
detection is missing. A shift of 8 m or more breaks most such associations
at shorter range, and few shifted copies reproduce them. In the tight
clusters the missed stems are therefore matched 0.12–0.37 more often than
the null recall at 4 m, already 0.12 and 0.25 more often for the baseline
and the skilled detector with every tree mapped, against 0.06–0.18 less
often in the unclustered stand. Corrected recall exceeds the truth only where
the missed stems are matched more often than the null recall, but not always
there, because a stem whose own detection a nearer stem takes can stay
unmatched. The corrected score therefore measures agreement beyond shifted
copies of the same detections; it is not an unbiased estimate of per-stem
skill, and its error has no fixed sign.

**(ii) With uniform commission, corrected F1 orders detectors by skill at
equal commission and penalises commission at equal skill in every setting,
and it discounts skill that comes with commission more than an oracle does**
(Tables 2 and 7). The oracle F1 counts only a stem's own detection within r
as a match. More skill at equal commission (b) gives positive corrected F1
leads in all 60 settings of scenario 4, which include Table 2's four: +0.023
to +0.066 on complete references and +0.007 to +0.029 on half ones, some of
the latter with narrow intervals (Table 9). More uniform commission at equal
skill (c) gives negative ones in every setting (−0.069 to −0.165 on complete
references, −0.045 to −0.108 on half ones), about as large as the oracle
leads or larger: by up to 0.025 in the unclustered stand, and in the
clustered stands at 4 m −0.119 to −0.165 against an oracle −0.092 to −0.106.
That extra uniform commission never gives a positive corrected F1 lead is
guaranteed by the null, in expectation: uniform points match as often after
a shift as before, and fewer stems are free for them before it, because the
skilled detections have taken theirs, so they add at least as much to the
null's counts as to the observed ones, while each of them enlarges F1's
denominator. More skill with more commission (a) gains
0.149 in true skilled share and 0.047 in oracle F1 at 4 m on the first
version's complete reference, but its corrected F1 lead is only +0.009
[−0.002, +0.019] (observed +0.026); at 2 m it is +0.024 against an oracle
+0.036. The cause is precision: the null overstates the chance matches of
detections that are not a stem's own, as it does for missed stems, so
corrected precision falls well below the oracle's (0.352 against 0.474 for
the baseline at 4 m), and further for a detector with more
commission (0.270 against 0.439 for (a)). This discount holds in every
structure and grows as the reference thins. On complete references at 4 m the
corrected F1 lead of (a) lies 0.024–0.081 below the oracle's in every
scenario-4 setting, and with 80% or 60% of the trees mapped it is negative in
all three structures (−0.013 to −0.063; every interval excludes zero, narrowly
in five of the six settings with 80% mapped), while the oracle lead stays
positive (+0.015 to +0.039). The corrected F1 leads of (a) and (b) stay below
their oracle leads in all 60 settings each, by 0.002–0.081. That ordering is
not algebraic: it comes from the null overstating the chance matches of the
detections that are not a stem's own, and it holds here because each
leader's extra detections are detections of its own trees or uniform
commission. It does not hold when the extra detections follow the trees
without finding the mapped stems ((iii)).

**(iii) Extra detections that follow the trees without finding the mapped stems
lift corrected F1 above the oracle, and in tight clusters above zero** (Tables 7
and 9). Comparison (d) gives the baseline split crowns: a second detection of a
crown it already detects, 1.5 to 4 m from the tree, at rate 0.5 (24–25% more
detections) or 0.8 (39–40% more), with no gain in skill. Its oracle F1 lead is
negative in every setting (−0.032 to −0.075 on complete references), as extra
commission makes it, but its corrected F1 lead lies above the oracle lead in all
60 settings of each rate, complete and half references alike. In the unclustered
stand the corrected lead stays negative (−0.025 to −0.059). At 4 m in the tight
clusters it turns positive with every tree or 80% of the trees mapped, up to
+0.048 [+0.041, +0.055] at rate 0.5 and +0.062 [+0.054, +0.071] at rate 0.8 with
every tree mapped, and it is negative with 60% mapped; at 2 m it is at most
+0.020. In the loose clusters at rate 0.8, the surplus of the benchmark's two
segmenters, it is −0.001 [−0.011, +0.008] with every tree mapped and −0.031 to
−0.055 with 80% or 60% mapped at 4 m; at rate 0.5 it reaches +0.011 [+0.003,
+0.019] with every tree mapped and is negative otherwise. Comparison (e), two
detectors without skill, shows the same mechanism without any skill at all: the
displaced detector leads the uniform detector by +0.057 to +0.099 in corrected
F1 at 4 m in the clustered stands, every interval excluding zero, against a true
difference of zero. The ordering of (ii) therefore depends on what the leader's
extra detections are: a corrected F1 lead understates a difference in skill when
they are of the leader's own trees or uniform, and overstates it when they lie
beside trees, as split crowns and detections of unmapped trees do.

**(iv) A corrected recall lead is not by itself evidence of skill** (Tables 2, 7
and 8). In the first version's settings the corrected recall leads of (a) and
(b) lie within 0.010 of the true skill difference. Extra uniform commission
alone (c) raises corrected recall by +0.025 [+0.010, +0.039] at 4 m on the
complete reference and by +0.026 [+0.003, +0.047] on the half one, a narrow
interval; at 2 m it raises it by +0.005 on both, with intervals that include
zero. On the complete references of scenario 4 the recall leads of (b) lie
within 0.016 of the true difference and those of (a) within 0.034, above it in
the clustered stands at 4 m (by 0.008–0.034, up to +0.188 against +0.154).
Uniform commission alone raises corrected recall at 4 m by +0.024 to +0.061 in
the clustered stands, every interval excluding zero, and by +0.006 to +0.060 in
the unclustered one; at 2 m by −0.003 to +0.015. Commission that follows the
trees raises it more: split crowns raise corrected recall at 4 m by +0.025 to
+0.052 in the unclustered stand, +0.066 to +0.126 in the loose clusters and
+0.092 to +0.194 in the tight ones (rates 0.5 and 0.8). The displaced detector,
without any skill, scores a corrected recall of +0.109 to +0.151 at 4 m in the
clustered stands (Table 8). The benchmark's two segmenters lead CHM-VWF in
corrected recall by 0.108 and 0.112 at 4 m, with 35–39% more core detections and
no lead in corrected precision ([chance
agreement](matcher-robustness-results.md#chance-agreement)). Split crowns at
rate 0.8, with about that surplus and no skill, give +0.094 to +0.126 in the
loose clusters, the pattern nearest to the benchmark's stems: split crowns alone
could produce the segmenters' corrected recall lead in such a stand, although
they do not produce a positive corrected F1 lead there ((iii)). A corrected
recall lead therefore credits a detector that places more detections, most of
all detections that follow the trees.

**(v) An unsampled half of the core cuts a real F1 lead to about half or
less, observed, corrected and in the oracle alike** (Tables 2 and 9). This
is a property of scoring an area half of which holds no reference, not of
the correction: every detection in the unsampled quadrants counts as
commission, in the observed score, in the null and in the oracle, so
precision halves for every detector and a leader's extra detections of
unmapped trees count against it. In the first version the (b) lead falls
from +0.060 to +0.025 corrected, from +0.041 to +0.020 observed and from
+0.075 to +0.043 in the oracle at 4 m, and from +0.050 to +0.025, from
+0.046 to +0.024 and from +0.057 to +0.032 at 2 m. For (a) the corrected
lead at 4 m changes sign, from +0.009 to −0.019 [−0.028, −0.009], and the
observed lead from +0.026 to −0.012, although the true skill gain is
essentially unchanged (+0.146). Recall leads barely move ((a) +0.151 and
+0.136; (b) +0.091 and +0.090). The same holds in every structure and
completeness of scenario 4: the (b) lead on the half reference is 0.28–0.56
of its complete-reference size when corrected, 0.10–0.58 when observed and
0.48–0.61 in the oracle, its corrected recall lead moves by 0.015 or less,
and the (a) lead is negative on every half reference (−0.001 to −0.041; at
4 m every interval excludes zero). That the oracle's lead falls too shows
that the cut is F1 arithmetic over an area without reference, not a
property of the null. In the benchmark, SegmentAnyTree's corrected lead over
CHM-VWF on the 57 censused plots is +0.029 [+0.000, +0.059] in the nominal
boxes and +0.063 [+0.016, +0.108] inside the censused subplots
([censused chance agreement](censused-chance-agreement-results.md)). A
doubling is what the simulation gives for a pure skill gain when every core is
half unsampled, but the benchmark is not that case. Of the 57 plots, 24 are
distributed plots, which are censused whole, so about two-fifths of the
nominal area is unsampled rather than half. On all 106 plots that study also
finds SegmentAnyTree's lead larger on the half-sampled tower plots (+0.042
[+0.015, +0.068]) than on the distributed plots (+0.022 [−0.028, +0.074]), the
opposite of what an unsampled half would do on its own. The simulated halving
therefore does not explain the benchmark's difference.

**(vi) Denser stands raise the null and shrink the corrected lead** (Table 3;
unclustered stand, complete reference). For comparison (a) at 4 m, the
baseline's null share rises from 33% of F1 at 60 trees/ha to 56%, 70% and 76%
at 150, 240 and 300 trees/ha. The corrected F1 lead is +0.052 [+0.037,
+0.068] at 60 trees/ha, close to the oracle's +0.062, but only +0.004 to
+0.009, with intervals that include zero, at 150–300 trees/ha, where the
oracle lead stays between +0.036 and +0.047. The corrected recall lead tracks
the true difference at every density (within 0.014).

**Check: the uniform detector without skill passes by construction; detectors
without skill whose detections follow the trees do not** (Tables 4, 7 and 8). In
the first version the uniform detector (s 0, f 1) has corrected recall −0.010 to
+0.008 and corrected F1 −0.008 to +0.007, every interval covering zero. In
scenario 4 its corrected recall is −0.025 to +0.027; 4 of 30 intervals exclude
zero, three of them narrowly, all in the clustered stands, whose rows share
plots and commission points. Uniform commission keeps its distribution under a
toroidal shift, so its expected corrected score is zero in any stand: this check
validates the code and shows the variation of one set of 200 plots, not the
null's behaviour when detections follow the trees. The two detectors built to
have no skill on the reference stems do follow the trees. Placed 5–10 m from
their trees, so that no stem's own detection lies within either radius, the
displaced detections give corrected recall +0.109 to +0.151 at 4 m and +0.024 to
+0.043 at 2 m in the clustered stands, whether every tree is mapped or not, and
corrected F1 up to +0.096; in the unclustered stand they score about zero
(−0.009 to +0.014). Paired with the uniform detector on the same plots, shifts
and resamples (comparison (e), Table 7), the displaced detector leads it in
corrected F1 by +0.057 to +0.099 at 4 m in the clustered stands, every interval
excluding zero, and by +0.011 to +0.025 at 2 m (one interval just reaching
zero), against −0.012 to +0.000 in the unclustered stand. A detector that finds
only the unmapped trees scores +0.044 to +0.135 with 80% of the trees mapped and
+0.101 to +0.310 with 60% mapped at 4 m in the clustered stands (corrected F1 up
to +0.277). In the unclustered stand it scores about zero, or below zero where
the unmapped trees keep their distance from the mapped ones (−0.043 [−0.061,
−0.024] at 400 trees/ha). "Above chance" therefore means that the detections lie
closer to the reference stems than shifted copies of the same detections do. In
a clustered stand that holds for any detector whose detections follow the trees,
mapped or not: a corrected score above zero shows that a detector's detections
follow the stand, not that it finds the reference stems, and how much of it is
skill on the reference depends on the structure.

**(vii) The benchmark's reference stems are slightly clustered, about as much
as the loose clusters** (Table 10). On the 54 distributed plots of the
population, which NEON censuses whole (SJER has none), a reference stem has on
average 3.05 other reference stems within 4 m, against 2.68 for as many stems
placed at random in the same 20 m box: a ratio of 1.14 [1.06, 1.21] and an
excess of +0.37 [+0.13, +0.63] stems. Within 2 m the ratio is 1.11 [0.86,
1.34] and the excess +0.08 [−0.08, +0.30]. By site the ratio within 4 m is
1.10 (WREF) to 1.30 (TEAK); within 2 m ABBY's stems are spaced out (0.66
[0.31, 0.96]), and SOAP's and TEAK's stand closer than at random (1.51 and
1.56). The ratio falls as density rises for clusters of a fixed size, while
the excess, observed minus random, does not, so the excess compares the
benchmark with the simulated stands without matching their densities. Within
4 m the loose clusters' excess is +0.41 and +0.38 at 240 and 400 trees/ha,
the tight clusters' +2.53 at both and the unclustered stand's −0.12 and
−0.22; within 2 m it is +0.14 and +0.12, +0.96 and +0.95, and −0.15 and
−0.25. The benchmark's +0.37 within 4 m matches the loose clusters, lies far
below the tight ones and excludes the unclustered stand. Within 2 m it cannot
be told apart from random or from the loose clusters, but it excludes both
the unclustered stand and the tight clusters. Mapping a random 60% of the
simulated trees leaves the ratios within 0.03 but scales the excess by about
0.6, since a cluster then holds fewer mapped trees (the loose clusters'
+0.41 within 4 m becomes +0.25, the tight clusters' +2.53 becomes +1.48), so
the tight clusters stay far above the benchmark either way. In ratios, at the
benchmark's density of about 400 stems/ha the loose clusters give 1.20 within
4 m and 1.24 within 2 m, the tight clusters 2.20 and 2.65, and the
unclustered stand 0.87 and 0.45. The benchmark's stems are thus far from the
tight clusters, close to the loose ones and more clustered than the
unclustered stand. This describes the mapped stems' own clustering only; it
says nothing about where the trees that the reference leaves out, or a
detector's commission, stand relative to them. Tower plots are left out,
because which of their quadrants were sampled cannot be read from the stems.

**What this means for the benchmark: the direction of its bias is not
established.** The simulated pattern closest to the benchmark's stems, the
loose clusters, gives a shortfall with every tree mapped (about 0.07 at 4 m)
that shrinks as the reference thins, to about zero at 240 trees/ha with 60%
mapped. The tight clusters, which give an excess, are unlike the benchmark
both in clustering and in their null shares (44–60% of the baseline's F1 at
4 m, against the benchmark's 70–79%; Table 5). But the sign depends on where
two things stand relative to the reference stems, the trees that a detector
can find but the reference leaves out and the detector's commission, and the
benchmark measures neither. Its reference leaves out stems below 10 cm DBH,
dead trees, census targets without a usable position and, on tower plots,
half of the core, and real commission falls on crowns and in the understory
rather than uniformly. The clustering of the reference stems alone does not
fix that relation: small unmapped trees standing beside mapped stems could
act like the tight clusters' unmapped trees, although the matcher's height
gate, which requires a detection to reach half a stem's height, keeps most
detections of trees under 10 cm DBH from matching tall mapped stems; split
crowns, dead trees and census targets without a usable position are not
limited that way. For the leads, the simulation identifies a condition
rather than a sign: a corrected F1 lead understates a difference in skill
when the leader's extra detections are of its own trees or uniform and
overstates it when they lie beside trees ((iii)), and the benchmark does not
measure which. In the loose clusters, split crowns at about the segmenters'
surplus of detections give no positive corrected F1 lead but reproduce their
corrected recall lead, so the segmenters' corrected F1 leads are not easily
produced by split crowns alone in a stand like the benchmark's, while their
corrected recall leads could be. No simulated setting reaches the
benchmark's mapped density either. The benchmark's corrected scores and leads
are therefore neither lower nor upper bounds on per-stem skill; they measure
agreement beyond shifted copies of the same detections.

**Calibration.** At 240 trees/ha the baseline (s 0.45, f 0.45) places 0.88
core detections per reference stem on a complete reference and 1.76 on a
half one, and detector (a) 1.27 and 2.55; the benchmark's leading detectors
place 1.0–1.4. In scenario 4 the baseline places 0.88–1.53 and the skilled
detector 1.09–1.87 (Table 5): the settings with 80% of the trees mapped lie in
the benchmark's range and those with 60% above it. The baseline's null reaches
70% of its F1 at 4 m, within the benchmark's 70–79%, but 40% at 2 m, below
the benchmark's 49–60%, probably because real apex offsets are wider than the
simulated 1.2 m. In scenario 4 the baseline's null share at 4 m is 70–83% in
the unclustered stand, 62–75% in the loose clusters and 44–60% in the tight
ones: the unclustered stand matches the benchmark's 70–79% best, the loose
clusters fall mostly below it and the tight clusters well below. By null
share the benchmark resembles the unclustered stand, by the clustering of its
stems the loose clusters (Table 10); neither measure alone places it. The
benchmark's 240 reference stems/ha, and so its 1.2 stems in a 4 m
circle, are averages over the nominal cores (2,525 stems over 10.48 ha, about
two-fifths of it unsampled tower area); on the distributed plots, censused
whole, the density is 406 stems/ha (Table 10).

## What is simulated

`simulate_chance_correction.R` builds synthetic tower plots and scores them
with the paper's functions from `sweep_lib.R`:

- **Plot.** A 40 m core with the 4 m matching margin (a 48 m scoring square),
  and trees over a 60 m square, so that detections near the edge of the
  scoring square come from trees inside and outside it.
- **Trees.** Scenarios 1 to 3 use sequential inhibition: a Poisson number of
  trees at D trees/ha, no two closer than 1.5 m, and placed at random beyond
  that minimum spacing. This report calls it the *unclustered stand*
  (`inhibited` in the code and the tables). Scenario 4 adds two Matérn
  cluster processes: cluster centres at D / μ per unit area over the 60 m
  square widened by R, each with a Poisson number of trees (mean μ) placed
  uniformly in a disc of radius R around it, with no minimum spacing. The
  *tight clusters* have R = 4 m and μ = 6, the *loose clusters* R = 8 m and
  μ = 4. Heights are lognormal with a median of 15 m and a log-scale spread
  of 0.4, clamped to 3–60 m, and do not depend on position. At 240 trees/ha
  a 4 m circle holds 1.2 trees on average, as the benchmark's nominal cores
  hold 1.2 reference stems. Around a tree, the unclustered stand holds 1.05
  other trees within 4 m, the loose clusters 2.0 and the tight clusters 4.7
  (Table 5). The unclustered stand's shortfall against a random pattern, a
  ratio of 0.87 within 4 m and 0.45 within 2 m (Table 10), is the area that
  the 1.5 m minimum spacing excludes (1 − 1.5²/4² = 0.86 and 1 − 1.5²/2² =
  0.44).
- **Detector.** Skill s and commission f: each tree is detected with
  probability s, at its position plus an isotropic Gaussian offset (sd 1.2 m
  per axis, for the offset between stem base and crown apex and the mapping
  error) and at its height plus a 1 m error. In addition, round(f × trees)
  commission points are placed uniformly over the 60 m square with heights
  from the tree-height distribution. All detectors on a plot share one random
  stream: a tree detected at skill 0.45 is also detected at skill 0.60, at the
  same place, and a detector with more commission keeps the other's
  commission points and adds more. The comparisons are therefore paired, as
  the paper's leads are.
- **Detectors without skill whose detections follow the trees** (scenario
  4). *Unmapped only* detects, with probability 0.8 and as above, each tree
  whose mapping draw leaves it out of the reference at the setting's p,
  inside the core or beyond it; with every tree mapped it places commission
  only. *Displaced* detects each tree with probability
  0.8 at a point 5 to 10 m from it (uniform over that ring, in a random
  direction), at the tree's height plus the 1 m error. Neither can place a
  stem's own detection within either radius, so both have no skill on the
  reference. Each adds round(0.3 × trees) commission points.
- **Split crowns** (scenario 4, second extension). The baseline's detections
  (s 0.45, f 0.45) plus, for each tree it detects whose split draw falls
  below the rate, 0.5 or 0.8, a second detection of the same crown, 1.5 to
  4 m from the tree (uniform in distance, in a random direction), at the
  tree's height plus the 1 m error. The second detections are commission in
  every score and in the oracle, so the detector has the baseline's skill
  and more detections, which follow the trees. Split crowns nest across the
  two rates.
- **Reference.** Every tree in the core (`complete`), or only the trees in
  two of the four 20 m quadrants of the core, the pair drawn per plot
  (`half`), as NEON samples a tower plot. The detector acts on all trees, so
  under `half` it also detects the trees in the unsampled quadrants.
- **Reference completeness** (scenario 4). Each tree is a reference stem with
  probability p ∈ {1, 0.8, 0.6}, from one draw per tree, so that the
  references nest; the other trees stay in the plot and every detector acts
  on them. At 240 trees/ha, held for every p, the references hold 240, 192 and
  144 stems/ha. The thinned ones are therefore sparser than the benchmark's
  240 reference stems/ha in the nominal cores, so the same p are also run with
  the reference density held at 240 stems/ha: 300 trees/ha at p = 0.8 and
  400 at p = 0.6. Commission is a share of all trees, so a detector places
  more core detections per reference stem as p falls (Table 5).
- **Truth.** The skilled share within r: the share of reference stems whose
  own skilled detection lies within r of the stem, counted from the simulated
  pairs. With sd 1.2 m its expectation is 0.996 s at 4 m and 0.75 s at 2 m.
  The truth ignores the matcher's height gate, which an own detection fails
  only for a tree of about 3 to 5 m with a large height error, under 0.01% of
  own detections. The oracle F1 counts as matches only these own detections;
  its precision is the share of core detections that are a reference stem's
  own detection within r. For the stems without such a detection (the missed
  stems), the share that the observed matcher pairs anyway is counted with
  the same greedy matcher, which reproduces `score_plot`'s true positives in
  every cell. The correction assumes that this share equals the null recall.
- **Scoring.** As in `paper_sensitivity.R MODE=null`: `score_plot` with the
  greedy matcher at r = 4 m or 2 m and the height gate (a detection between
  half the stem's height and that height plus 8 m); 200 toroidal shifts per
  plot and radius from `null_offset(2 (20 + r), seed, min_shift = 8)` and
  `shift_detections` within 20 + r, shared by every detector and reference;
  a cell's null is its mean counts over the shifts; scores pool summed counts
  over 200 plots; corrected recall, precision and F1 are computed from the
  pooled scores. Intervals are 95% percentile intervals from the master
  tables' paired plot bootstrap (1,000 resamples), shared by every detector
  of a setting.
- **Scenarios.** (1) Single detectors, s ∈ {0.2, 0.4, 0.6, 0.8} × f ∈ {0.3,
  1.0}, both references, both radii, 240 trees/ha. (2) Three detectors against
  a baseline (s 0.45, f 0.45): (a) more skill and more commission (s 0.60,
  f 0.70), (b) more skill at equal commission (s 0.55, f 0.45), (c) equal
  skill and more commission (s 0.45, f 1.0), same settings. (3) Comparison
  (a) at 60, 150 and 300 trees/ha, complete reference, 4 m, beside the
  240 trees/ha row of scenario 2. A detector without skill (s 0, f 1) runs in
  every setting. (4) Stand structure and reference completeness: the three
  patterns, each at p = 1, 0.8 and 0.6 with 240 trees/ha and at p = 0.8 and
  0.6 with 240 reference stems/ha, complete and half references, both radii;
  the detectors are the baseline, (a), (b) and (c) of scenario 2, a skilled
  detector (s 0.8, f 0.3), the detector without skill (s 0, f 1), the two
  detectors without skill whose detections follow the trees and, from the
  second extension, the two split-crown detectors. Two comparisons come with
  the second extension: (d) the baseline with split crowns at rate 0.5 and at
  rate 0.8 against the baseline, on the grid of (a) to (c); (e) the displaced
  detector against the uniform detector without skill, on complete
  references, both radii and all 15 settings. Every comparison is a paired
  lead with the shared plot bootstrap. Scenario 4's unclustered plots at 240
  and 300 trees/ha are those of scenarios 2 and 3: the draws for p and for the
  displaced detector come after all others, so the trees, detections and
  shifts are the same, and its fully mapped unclustered rows reproduce
  scenario 2's pooled rows exactly, which the script checks (a failed check
  stops the run before any pooled output of scenario 4 is written). The
  split-crown draws come after those, so the second extension left every
  earlier output unchanged.

## What is not simulated

The plots are synthetic point patterns, not forests. There are no crowns, no
canopy height model and no layering: every tree is equally detectable, the
offset between a stem and its detection does not grow with tree size, and
commission is uniform and independent of the trees, except for the detectors
of scenario 4 whose detections follow the trees (the two without skill and
the split crowns), whereas real commission clusters on large crowns and in
the understory. The split crowns are one simple form of commission that
follows the trees: a second detection at a uniform 1.5 to 4 m from the tree,
in a random direction and at the tree's height, whatever the crown's size.
Which trees are left out of the reference is random and independent of their
position and size, so the simulated unmapped trees are as tall as the mapped
ones and the matcher's height gate does not keep their detections from
matching mapped stems. The benchmark's detectable trees outside the reference
are particular ones (stems below 10 cm DBH, dead trees, census targets
without a usable position, and the trees of unsampled quadrants), and how
they stand relative to the reference stems is not known. The clustered
patterns have no minimum spacing. All
plots are tower plots; the distributed 20 m plots, which NEON censuses whole,
are not modelled. No setting reaches the reference density of the
benchmark's censused area, about 400 stems/ha (Table 10). The study therefore
shows the direction and rough size of the statistic's behaviour under each
structure; it does not reproduce the benchmark's numbers, and it cannot by
itself give the sign of the benchmark's bias.

## Tables

Tables 1 to 4 are at 240 trees/ha unless stated, in the unclustered stand
(`inhibited` in Tables 5 to 9, which are scenario 4's; there "clustered 4 m"
is the tight clusters and "clustered 8 m" the loose ones). Every setting has
200 plots and 200 shifts
per plot, except that 3 or 4 of the 200 tight-cluster plots hold no stem in
their half reference at 240 and 300 trees/ha and drop out of those rows, as
the paper skips such plots. Null share is null F1 / F1. Missed stems matched
is the share of the reference stems without their own detection within r
that the observed matcher pairs anyway; the correction assumes it equals the
null recall.

### Table 1. Single detectors

| Reference | r (m) | s | f | Recall | Precision | F1 | Null F1 | Null share | True skilled share | Corrected recall | Corrected recall - truth [95% CI] | Corrected F1 | Null recall | Missed stems matched |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| complete | 4 | 0.2 | 0.3 | 0.351 | 0.648 | 0.455 | 0.340 | 75% | 0.196 | 0.119 | -0.077 [-0.086, -0.066] | 0.175 | 0.263 | 0.206 |
| complete | 4 | 0.4 | 0.3 | 0.516 | 0.695 | 0.592 | 0.394 | 67% | 0.387 | 0.259 | -0.128 [-0.138, -0.118] | 0.327 | 0.346 | 0.240 |
| complete | 4 | 0.6 | 0.3 | 0.679 | 0.719 | 0.698 | 0.430 | 62% | 0.584 | 0.442 | -0.142 [-0.152, -0.131] | 0.471 | 0.424 | 0.280 |
| complete | 4 | 0.8 | 0.3 | 0.835 | 0.727 | 0.777 | 0.452 | 58% | 0.785 | 0.674 | -0.111 [-0.121, -0.101] | 0.594 | 0.495 | 0.329 |
| complete | 4 | 0.2 | 1.0 | 0.592 | 0.458 | 0.517 | 0.460 | 89% | 0.196 | 0.133 | -0.063 [-0.081, -0.043] | 0.105 | 0.529 | 0.499 |
| complete | 4 | 0.4 | 1.0 | 0.704 | 0.476 | 0.568 | 0.466 | 82% | 0.387 | 0.288 | -0.100 [-0.117, -0.080] | 0.190 | 0.584 | 0.531 |
| complete | 4 | 0.6 | 1.0 | 0.807 | 0.482 | 0.603 | 0.467 | 77% | 0.584 | 0.472 | -0.112 [-0.130, -0.094] | 0.256 | 0.635 | 0.563 |
| complete | 4 | 0.8 | 1.0 | 0.903 | 0.482 | 0.629 | 0.464 | 74% | 0.785 | 0.697 | -0.088 [-0.102, -0.073] | 0.308 | 0.680 | 0.599 |
| complete | 2 | 0.2 | 0.3 | 0.207 | 0.402 | 0.273 | 0.124 | 45% | 0.144 | 0.125 | -0.019 [-0.025, -0.014] | 0.170 | 0.094 | 0.078 |
| complete | 2 | 0.4 | 0.3 | 0.349 | 0.489 | 0.407 | 0.149 | 37% | 0.291 | 0.253 | -0.037 [-0.043, -0.032] | 0.303 | 0.128 | 0.095 |
| complete | 2 | 0.6 | 0.3 | 0.488 | 0.532 | 0.509 | 0.168 | 33% | 0.437 | 0.389 | -0.048 [-0.053, -0.043] | 0.409 | 0.162 | 0.110 |
| complete | 2 | 0.8 | 0.3 | 0.626 | 0.556 | 0.589 | 0.183 | 31% | 0.586 | 0.536 | -0.051 [-0.056, -0.045] | 0.497 | 0.195 | 0.126 |
| complete | 2 | 0.2 | 1.0 | 0.312 | 0.252 | 0.279 | 0.189 | 68% | 0.144 | 0.127 | -0.018 [-0.027, -0.008] | 0.110 | 0.212 | 0.200 |
| complete | 2 | 0.4 | 1.0 | 0.439 | 0.306 | 0.360 | 0.198 | 55% | 0.291 | 0.260 | -0.031 [-0.040, -0.022] | 0.203 | 0.242 | 0.218 |
| complete | 2 | 0.6 | 1.0 | 0.560 | 0.342 | 0.425 | 0.205 | 48% | 0.437 | 0.396 | -0.040 [-0.049, -0.032] | 0.277 | 0.271 | 0.234 |
| complete | 2 | 0.8 | 1.0 | 0.679 | 0.368 | 0.477 | 0.210 | 44% | 0.586 | 0.541 | -0.045 [-0.053, -0.036] | 0.339 | 0.300 | 0.247 |
| half | 4 | 0.2 | 0.3 | 0.362 | 0.337 | 0.349 | 0.256 | 73% | 0.200 | 0.128 | -0.072 [-0.089, -0.055] | 0.124 | 0.269 | 0.218 |
| half | 4 | 0.4 | 0.3 | 0.524 | 0.355 | 0.423 | 0.281 | 66% | 0.391 | 0.265 | -0.126 [-0.143, -0.109] | 0.198 | 0.353 | 0.250 |
| half | 4 | 0.6 | 0.3 | 0.683 | 0.364 | 0.475 | 0.293 | 62% | 0.581 | 0.443 | -0.138 [-0.155, -0.121] | 0.257 | 0.431 | 0.295 |
| half | 4 | 0.8 | 0.3 | 0.839 | 0.366 | 0.510 | 0.297 | 58% | 0.777 | 0.677 | -0.100 [-0.117, -0.082] | 0.302 | 0.502 | 0.354 |
| half | 4 | 0.2 | 1.0 | 0.601 | 0.235 | 0.337 | 0.298 | 88% | 0.200 | 0.138 | -0.062 [-0.090, -0.030] | 0.056 | 0.537 | 0.508 |
| half | 4 | 0.4 | 1.0 | 0.709 | 0.241 | 0.360 | 0.295 | 82% | 0.391 | 0.287 | -0.104 [-0.133, -0.073] | 0.093 | 0.592 | 0.536 |
| half | 4 | 0.6 | 1.0 | 0.807 | 0.243 | 0.373 | 0.289 | 78% | 0.581 | 0.461 | -0.119 [-0.146, -0.091] | 0.118 | 0.642 | 0.568 |
| half | 4 | 0.8 | 1.0 | 0.904 | 0.242 | 0.381 | 0.282 | 74% | 0.777 | 0.692 | -0.085 [-0.107, -0.061] | 0.138 | 0.687 | 0.606 |
| half | 2 | 0.2 | 0.3 | 0.210 | 0.204 | 0.207 | 0.093 | 45% | 0.147 | 0.127 | -0.020 [-0.027, -0.012] | 0.126 | 0.094 | 0.078 |
| half | 2 | 0.4 | 0.3 | 0.349 | 0.245 | 0.288 | 0.105 | 37% | 0.290 | 0.254 | -0.037 [-0.045, -0.029] | 0.204 | 0.128 | 0.094 |
| half | 2 | 0.6 | 0.3 | 0.483 | 0.264 | 0.342 | 0.114 | 33% | 0.431 | 0.383 | -0.048 [-0.056, -0.039] | 0.257 | 0.162 | 0.107 |
| half | 2 | 0.8 | 0.3 | 0.619 | 0.275 | 0.381 | 0.120 | 31% | 0.575 | 0.526 | -0.049 [-0.057, -0.041] | 0.297 | 0.196 | 0.122 |
| half | 2 | 0.2 | 1.0 | 0.314 | 0.127 | 0.181 | 0.122 | 68% | 0.147 | 0.129 | -0.018 [-0.032, -0.003] | 0.067 | 0.213 | 0.199 |
| half | 2 | 0.4 | 1.0 | 0.439 | 0.153 | 0.227 | 0.125 | 55% | 0.290 | 0.260 | -0.030 [-0.043, -0.015] | 0.117 | 0.242 | 0.218 |
| half | 2 | 0.6 | 1.0 | 0.556 | 0.170 | 0.261 | 0.126 | 48% | 0.431 | 0.390 | -0.040 [-0.054, -0.026] | 0.154 | 0.271 | 0.231 |
| half | 2 | 0.8 | 1.0 | 0.672 | 0.183 | 0.287 | 0.127 | 44% | 0.575 | 0.531 | -0.044 [-0.056, -0.031] | 0.183 | 0.300 | 0.244 |

### Table 2. Paired leads over the baseline (s 0.45, f 0.45)

| Comparison | Reference | r (m) | True skill difference | Observed F1 lead | Corrected F1 lead | Corrected recall lead | Oracle F1 lead |
| --- | --- | --- | --- | --- | --- | --- | --- |
| (a) more skill, more commission | complete | 4 | +0.149 | +0.026 [+0.019, +0.032] | +0.009 [-0.002, +0.019] | +0.151 [+0.137, +0.164] | +0.047 |
| (a) more skill, more commission | complete | 2 | +0.112 | +0.036 [+0.030, +0.043] | +0.024 [+0.017, +0.032] | +0.108 [+0.099, +0.117] | +0.036 |
| (a) more skill, more commission | half | 4 | +0.146 | -0.012 [-0.018, -0.005] | -0.019 [-0.028, -0.009] | +0.136 [+0.116, +0.158] | +0.011 |
| (a) more skill, more commission | half | 2 | +0.109 | +0.004 [-0.002, +0.012] | -0.003 [-0.010, +0.005] | +0.101 [+0.089, +0.115] | +0.009 |
| (b) more skill, equal commission | complete | 4 | +0.099 | +0.041 [+0.037, +0.046] | +0.060 [+0.053, +0.068] | +0.091 [+0.082, +0.100] | +0.075 |
| (b) more skill, equal commission | complete | 2 | +0.075 | +0.046 [+0.042, +0.051] | +0.050 [+0.045, +0.056] | +0.069 [+0.063, +0.076] | +0.057 |
| (b) more skill, equal commission | half | 4 | +0.097 | +0.020 [+0.015, +0.024] | +0.025 [+0.019, +0.032] | +0.090 [+0.077, +0.103] | +0.043 |
| (b) more skill, equal commission | half | 2 | +0.072 | +0.024 [+0.020, +0.029] | +0.025 [+0.020, +0.030] | +0.066 [+0.058, +0.075] | +0.032 |
| (c) equal skill, more commission | complete | 4 | +0.000 | -0.039 [-0.046, -0.033] | -0.119 [-0.130, -0.109] | +0.025 [+0.010, +0.039] | -0.105 |
| (c) equal skill, more commission | complete | 2 | +0.000 | -0.044 [-0.048, -0.039] | -0.082 [-0.087, -0.076] | +0.005 [-0.001, +0.011] | -0.078 |
| (c) equal skill, more commission | half | 4 | +0.000 | -0.056 [-0.062, -0.049] | -0.079 [-0.088, -0.069] | +0.026 [+0.003, +0.047] | -0.088 |
| (c) equal skill, more commission | half | 2 | +0.000 | -0.049 [-0.053, -0.043] | -0.066 [-0.071, -0.060] | +0.005 [-0.004, +0.015] | -0.066 |

### Table 3. Lead of (a) over the baseline by tree density

Complete reference, 4 m. Reference stems are summed over the 200 plots; the
240 trees/ha row is scenario 2's.

| Trees/ha | Reference stems | Baseline null share | True skill difference | Observed F1 lead | Corrected F1 lead | Corrected recall lead | Oracle F1 lead |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 60 | 1867 | 33% | +0.172 | +0.057 [+0.044, +0.071] | +0.052 [+0.037, +0.068] | +0.176 [+0.157, +0.196] | +0.062 |
| 150 | 4711 | 56% | +0.141 | +0.024 [+0.016, +0.033] | +0.007 [-0.004, +0.020] | +0.146 [+0.132, +0.163] | +0.036 |
| 240 | 7562 | 70% | +0.149 | +0.026 [+0.019, +0.032] | +0.009 [-0.002, +0.019] | +0.151 [+0.137, +0.164] | +0.047 |
| 300 | 9401 | 76% | +0.147 | +0.021 [+0.015, +0.027] | +0.004 [-0.008, +0.014] | +0.161 [+0.146, +0.174] | +0.042 |

### Table 4. Detector without skill (s 0, f 1)

| Trees/ha | Reference | r (m) | Observed F1 | Null F1 | Corrected recall [95% CI] | Corrected F1 [95% CI] |
| --- | --- | --- | --- | --- | --- | --- |
| 240 | complete | 4 | 0.448 | 0.447 | +0.002 [-0.017, +0.021] | +0.002 [-0.014, +0.019] |
| 240 | complete | 2 | 0.184 | 0.178 | +0.008 [-0.001, +0.017] | +0.007 [-0.002, +0.016] |
| 240 | half | 4 | 0.298 | 0.299 | -0.008 [-0.036, +0.023] | -0.001 [-0.015, +0.013] |
| 240 | half | 2 | 0.122 | 0.118 | +0.007 [-0.007, +0.021] | +0.004 [-0.004, +0.013] |
| 60 | complete | 4 | 0.167 | 0.173 | -0.010 [-0.029, +0.011] | -0.008 [-0.025, +0.011] |
| 150 | complete | 4 | 0.343 | 0.339 | +0.002 [-0.016, +0.021] | +0.006 [-0.011, +0.023] |
| 300 | complete | 4 | 0.497 | 0.498 | -0.000 [-0.017, +0.016] | -0.002 [-0.015, +0.012] |

### Table 5. Stand structure and reference completeness: the settings

p is the share of trees mapped; "density held" says whether the row holds
240 trees/ha or 240 reference stems/ha. Reference stems per hectare are
counted over all 200 plots. Other stems within d is the mean number of
other reference stems within d of a reference stem, counted over the whole
simulated square (no edge loss). Core detections per stem and the baseline
null share are on the complete reference.

| Pattern | p | Trees/ha | Density held | Reference stems/ha | Other stems within 2 m | Other stems within 4 m | Core detections per stem: baseline | Core detections per stem: skilled | Baseline null share 4 m | Baseline null share 2 m |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| inhibited | 1.0 | 240 | both | 236 | 0.14 | 1.05 | 0.88 | 1.09 | 70% | 40% |
| inhibited | 0.8 | 240 | total density | 188 | 0.12 | 0.83 | 1.10 | 1.36 | 70% | 41% |
| inhibited | 0.6 | 240 | total density | 141 | 0.09 | 0.62 | 1.47 | 1.82 | 70% | 41% |
| inhibited | 0.8 | 300 | reference density | 234 | 0.14 | 1.02 | 1.14 | 1.40 | 76% | 47% |
| inhibited | 0.6 | 400 | reference density | 237 | 0.14 | 1.05 | 1.52 | 1.85 | 83% | 56% |
| clustered 4 m | 1.0 | 240 | both | 234 | 1.48 | 4.73 | 0.91 | 1.11 | 45% | 27% |
| clustered 4 m | 0.8 | 240 | total density | 186 | 1.18 | 3.73 | 1.14 | 1.40 | 44% | 26% |
| clustered 4 m | 0.6 | 240 | total density | 139 | 0.88 | 2.79 | 1.53 | 1.87 | 45% | 26% |
| clustered 4 m | 0.8 | 300 | reference density | 239 | 1.27 | 4.02 | 1.12 | 1.37 | 51% | 32% |
| clustered 4 m | 0.6 | 400 | reference density | 237 | 0.99 | 3.29 | 1.51 | 1.83 | 60% | 39% |
| clustered 8 m | 1.0 | 240 | both | 249 | 0.55 | 2.04 | 0.90 | 1.10 | 62% | 38% |
| clustered 8 m | 0.8 | 240 | total density | 199 | 0.44 | 1.64 | 1.13 | 1.38 | 62% | 37% |
| clustered 8 m | 0.6 | 240 | total density | 149 | 0.33 | 1.24 | 1.51 | 1.85 | 62% | 37% |
| clustered 8 m | 0.8 | 300 | reference density | 240 | 0.48 | 1.84 | 1.13 | 1.38 | 66% | 41% |
| clustered 8 m | 0.6 | 400 | reference density | 232 | 0.42 | 1.61 | 1.53 | 1.87 | 75% | 49% |

### Table 6. Baseline and skilled detectors by setting

Complete reference. Baseline: s 0.45, f 0.45; skilled: s 0.8, f 0.3.

| Pattern | p | Trees/ha | r (m) | Detector | Recall | Null recall | True skilled share | Corrected recall - truth [95% CI] | Missed stems matched | Corrected F1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| inhibited | 1.0 | 240 | 4 | baseline | 0.601 | 0.423 | 0.435 | -0.127 [-0.140, -0.115] | 0.326 | 0.329 |
| inhibited | 1.0 | 240 | 4 | skilled | 0.835 | 0.495 | 0.785 | -0.111 [-0.121, -0.101] | 0.329 | 0.594 |
| inhibited | 1.0 | 240 | 2 | baseline | 0.402 | 0.162 | 0.325 | -0.038 [-0.045, -0.032] | 0.129 | 0.304 |
| inhibited | 1.0 | 240 | 2 | skilled | 0.626 | 0.195 | 0.586 | -0.051 [-0.056, -0.045] | 0.126 | 0.497 |
| inhibited | 0.8 | 240 | 4 | baseline | 0.624 | 0.442 | 0.431 | -0.105 [-0.119, -0.089] | 0.365 | 0.286 |
| inhibited | 0.8 | 240 | 4 | skilled | 0.852 | 0.514 | 0.783 | -0.089 [-0.100, -0.077] | 0.388 | 0.487 |
| inhibited | 0.8 | 240 | 2 | baseline | 0.401 | 0.163 | 0.318 | -0.035 [-0.043, -0.027] | 0.132 | 0.262 |
| inhibited | 0.8 | 240 | 2 | skilled | 0.629 | 0.197 | 0.581 | -0.042 [-0.049, -0.036] | 0.139 | 0.429 |
| inhibited | 0.6 | 240 | 4 | baseline | 0.653 | 0.461 | 0.434 | -0.078 [-0.096, -0.057] | 0.404 | 0.238 |
| inhibited | 0.6 | 240 | 4 | skilled | 0.868 | 0.534 | 0.782 | -0.064 [-0.077, -0.052] | 0.445 | 0.369 |
| inhibited | 0.6 | 240 | 2 | baseline | 0.405 | 0.165 | 0.320 | -0.033 [-0.042, -0.024] | 0.134 | 0.219 |
| inhibited | 0.6 | 240 | 2 | skilled | 0.635 | 0.199 | 0.582 | -0.038 [-0.045, -0.030] | 0.144 | 0.350 |
| inhibited | 0.8 | 300 | 4 | baseline | 0.661 | 0.509 | 0.451 | -0.141 [-0.156, -0.127] | 0.406 | 0.260 |
| inhibited | 0.8 | 300 | 4 | skilled | 0.871 | 0.588 | 0.801 | -0.115 [-0.127, -0.103] | 0.413 | 0.446 |
| inhibited | 0.8 | 300 | 2 | baseline | 0.431 | 0.201 | 0.341 | -0.053 [-0.062, -0.045] | 0.152 | 0.258 |
| inhibited | 0.8 | 300 | 2 | skilled | 0.651 | 0.242 | 0.602 | -0.062 [-0.069, -0.055] | 0.155 | 0.417 |
| inhibited | 0.6 | 400 | 4 | baseline | 0.737 | 0.618 | 0.447 | -0.136 [-0.155, -0.116] | 0.544 | 0.179 |
| inhibited | 0.6 | 400 | 4 | skilled | 0.907 | 0.700 | 0.794 | -0.105 [-0.122, -0.089] | 0.594 | 0.278 |
| inhibited | 0.6 | 400 | 2 | baseline | 0.464 | 0.261 | 0.337 | -0.062 [-0.073, -0.052] | 0.205 | 0.197 |
| inhibited | 0.6 | 400 | 2 | skilled | 0.681 | 0.312 | 0.601 | -0.065 [-0.073, -0.057] | 0.224 | 0.321 |
| clustered 4 m | 1.0 | 240 | 4 | baseline | 0.586 | 0.266 | 0.444 | -0.007 [-0.016, +0.004] | 0.381 | 0.438 |
| clustered 4 m | 1.0 | 240 | 4 | skilled | 0.843 | 0.287 | 0.794 | -0.015 [-0.023, -0.005] | 0.532 | 0.688 |
| clustered 4 m | 1.0 | 240 | 2 | baseline | 0.427 | 0.115 | 0.334 | +0.019 [+0.011, +0.026] | 0.221 | 0.361 |
| clustered 4 m | 1.0 | 240 | 2 | skilled | 0.665 | 0.129 | 0.601 | +0.015 [+0.008, +0.023] | 0.326 | 0.563 |
| clustered 4 m | 0.8 | 240 | 4 | baseline | 0.653 | 0.294 | 0.449 | +0.059 [+0.046, +0.073] | 0.460 | 0.433 |
| clustered 4 m | 0.8 | 240 | 4 | skilled | 0.887 | 0.314 | 0.799 | +0.037 [+0.026, +0.048] | 0.635 | 0.617 |
| clustered 4 m | 0.8 | 240 | 2 | baseline | 0.467 | 0.124 | 0.337 | +0.055 [+0.046, +0.065] | 0.258 | 0.351 |
| clustered 4 m | 0.8 | 240 | 2 | skilled | 0.704 | 0.138 | 0.604 | +0.053 [+0.044, +0.063] | 0.374 | 0.518 |
| clustered 4 m | 0.6 | 240 | 4 | baseline | 0.718 | 0.328 | 0.449 | +0.131 [+0.114, +0.150] | 0.542 | 0.393 |
| clustered 4 m | 0.6 | 240 | 4 | skilled | 0.925 | 0.345 | 0.801 | +0.085 [+0.074, +0.097] | 0.715 | 0.509 |
| clustered 4 m | 0.6 | 240 | 2 | baseline | 0.500 | 0.133 | 0.339 | +0.084 [+0.072, +0.098] | 0.288 | 0.315 |
| clustered 4 m | 0.6 | 240 | 2 | skilled | 0.738 | 0.147 | 0.609 | +0.083 [+0.071, +0.095] | 0.414 | 0.444 |
| clustered 4 m | 0.8 | 300 | 4 | baseline | 0.663 | 0.341 | 0.448 | +0.040 [+0.026, +0.054] | 0.486 | 0.420 |
| clustered 4 m | 0.8 | 300 | 4 | skilled | 0.895 | 0.366 | 0.794 | +0.040 [+0.030, +0.050] | 0.650 | 0.617 |
| clustered 4 m | 0.8 | 300 | 2 | baseline | 0.472 | 0.150 | 0.342 | +0.037 [+0.029, +0.046] | 0.268 | 0.344 |
| clustered 4 m | 0.8 | 300 | 2 | skilled | 0.702 | 0.169 | 0.600 | +0.041 [+0.032, +0.050] | 0.377 | 0.511 |
| clustered 4 m | 0.6 | 400 | 4 | baseline | 0.764 | 0.462 | 0.456 | +0.106 [+0.091, +0.122] | 0.627 | 0.358 |
| clustered 4 m | 0.6 | 400 | 4 | skilled | 0.938 | 0.489 | 0.803 | +0.075 [+0.066, +0.084] | 0.788 | 0.467 |
| clustered 4 m | 0.6 | 400 | 2 | baseline | 0.531 | 0.208 | 0.343 | +0.065 [+0.055, +0.076] | 0.342 | 0.299 |
| clustered 4 m | 0.6 | 400 | 2 | skilled | 0.746 | 0.231 | 0.597 | +0.073 [+0.063, +0.083] | 0.462 | 0.422 |
| clustered 8 m | 1.0 | 240 | 4 | baseline | 0.611 | 0.382 | 0.443 | -0.073 [-0.085, -0.061] | 0.368 | 0.382 |
| clustered 8 m | 1.0 | 240 | 4 | skilled | 0.848 | 0.435 | 0.799 | -0.069 [-0.079, -0.060] | 0.425 | 0.638 |
| clustered 8 m | 1.0 | 240 | 2 | baseline | 0.419 | 0.158 | 0.331 | -0.021 [-0.028, -0.013] | 0.168 | 0.321 |
| clustered 8 m | 1.0 | 240 | 2 | skilled | 0.647 | 0.186 | 0.595 | -0.029 [-0.037, -0.022] | 0.209 | 0.519 |
| clustered 8 m | 0.8 | 240 | 4 | baseline | 0.652 | 0.407 | 0.446 | -0.033 [-0.047, -0.018] | 0.423 | 0.355 |
| clustered 8 m | 0.8 | 240 | 4 | skilled | 0.879 | 0.460 | 0.804 | -0.029 [-0.040, -0.017] | 0.506 | 0.549 |
| clustered 8 m | 0.8 | 240 | 2 | baseline | 0.437 | 0.163 | 0.334 | -0.006 [-0.015, +0.003] | 0.186 | 0.297 |
| clustered 8 m | 0.8 | 240 | 2 | skilled | 0.668 | 0.192 | 0.601 | -0.012 [-0.020, -0.003] | 0.231 | 0.465 |
| clustered 8 m | 0.6 | 240 | 4 | baseline | 0.690 | 0.435 | 0.439 | +0.013 [-0.006, +0.031] | 0.485 | 0.298 |
| clustered 8 m | 0.6 | 240 | 4 | skilled | 0.900 | 0.489 | 0.800 | +0.005 [-0.009, +0.020] | 0.578 | 0.424 |
| clustered 8 m | 0.6 | 240 | 2 | baseline | 0.448 | 0.168 | 0.328 | +0.009 [-0.002, +0.019] | 0.198 | 0.251 |
| clustered 8 m | 0.6 | 240 | 2 | skilled | 0.686 | 0.197 | 0.601 | +0.008 [-0.002, +0.018] | 0.257 | 0.388 |
| clustered 8 m | 0.8 | 300 | 4 | baseline | 0.677 | 0.451 | 0.459 | -0.048 [-0.063, -0.032] | 0.448 | 0.349 |
| clustered 8 m | 0.8 | 300 | 4 | skilled | 0.884 | 0.504 | 0.805 | -0.038 [-0.049, -0.028] | 0.517 | 0.529 |
| clustered 8 m | 0.8 | 300 | 2 | baseline | 0.453 | 0.188 | 0.348 | -0.021 [-0.029, -0.013] | 0.194 | 0.297 |
| clustered 8 m | 0.8 | 300 | 2 | skilled | 0.671 | 0.221 | 0.605 | -0.028 [-0.037, -0.019] | 0.226 | 0.452 |
| clustered 8 m | 0.6 | 400 | 4 | baseline | 0.742 | 0.563 | 0.445 | -0.034 [-0.053, -0.016] | 0.564 | 0.245 |
| clustered 8 m | 0.6 | 400 | 4 | skilled | 0.917 | 0.623 | 0.798 | -0.018 [-0.029, -0.005] | 0.650 | 0.353 |
| clustered 8 m | 0.6 | 400 | 2 | baseline | 0.487 | 0.243 | 0.332 | -0.009 [-0.019, +0.001] | 0.251 | 0.234 |
| clustered 8 m | 0.6 | 400 | 2 | skilled | 0.706 | 0.284 | 0.602 | -0.013 [-0.022, -0.004] | 0.309 | 0.357 |

### Table 7. Paired leads by setting

Complete reference. Over the baseline (s 0.45, f 0.45): (a) more skill and
more commission (s 0.60, f 0.70), (b) more skill at equal commission (s 0.55,
f 0.45), (c) equal skill and more uniform commission (s 0.45, f 1.0), (d) 0.5
and (d) 0.8, equal skill with split crowns at rate 0.5 and 0.8. (e) is the
displaced detector over the uniform detector without skill: neither has an
own detection, so their true difference is zero and the oracle scores
neither (n/a). Detections vs base: the leader's core detections per
reference stem against its base's. The inhibited rows of (a) to (c) at p = 1
are Table 2's.

| Pattern | p | Trees/ha | r (m) | Comparison | Detections vs base | True skill difference | Observed F1 lead | Corrected F1 lead | Corrected recall lead | Oracle F1 lead |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| inhibited | 1.0 | 240 | 4 | (a) | +45% | +0.149 | +0.026 [+0.019, +0.032] | +0.009 [-0.002, +0.019] | +0.151 [+0.137, +0.164] | +0.047 |
| inhibited | 1.0 | 240 | 4 | (b) | +11% | +0.099 | +0.041 [+0.037, +0.046] | +0.060 [+0.053, +0.068] | +0.091 [+0.082, +0.100] | +0.075 |
| inhibited | 1.0 | 240 | 4 | (c) | +63% | +0.000 | -0.039 [-0.046, -0.033] | -0.119 [-0.130, -0.109] | +0.025 [+0.010, +0.039] | -0.105 |
| inhibited | 1.0 | 240 | 4 | (d) 0.5 | +25% | +0.000 | -0.015 [-0.019, -0.010] | -0.028 [-0.036, -0.020] | +0.034 [+0.026, +0.043] | -0.048 |
| inhibited | 1.0 | 240 | 4 | (d) 0.8 | +39% | +0.000 | -0.026 [-0.032, -0.020] | -0.047 [-0.056, -0.036] | +0.052 [+0.042, +0.063] | -0.072 |
| inhibited | 1.0 | 240 | 4 | (e) | +10% | +0.000 | +0.001 [-0.009, +0.011] | -0.006 [-0.025, +0.013] | +0.001 [-0.021, +0.022] | n/a |
| inhibited | 1.0 | 240 | 2 | (a) | +45% | +0.112 | +0.036 [+0.030, +0.043] | +0.024 [+0.017, +0.032] | +0.108 [+0.099, +0.117] | +0.036 |
| inhibited | 1.0 | 240 | 2 | (b) | +11% | +0.075 | +0.046 [+0.042, +0.051] | +0.050 [+0.045, +0.056] | +0.069 [+0.063, +0.076] | +0.057 |
| inhibited | 1.0 | 240 | 2 | (c) | +63% | +0.000 | -0.044 [-0.048, -0.039] | -0.082 [-0.087, -0.076] | +0.005 [-0.001, +0.011] | -0.078 |
| inhibited | 1.0 | 240 | 2 | (d) 0.5 | +25% | +0.000 | -0.014 [-0.018, -0.010] | -0.025 [-0.030, -0.020] | +0.013 [+0.008, +0.018] | -0.036 |
| inhibited | 1.0 | 240 | 2 | (d) 0.8 | +39% | +0.000 | -0.022 [-0.027, -0.017] | -0.039 [-0.045, -0.033] | +0.021 [+0.015, +0.027] | -0.054 |
| inhibited | 1.0 | 240 | 2 | (e) | +10% | +0.000 | -0.005 [-0.014, +0.003] | -0.012 [-0.022, -0.002] | -0.012 [-0.023, -0.000] | n/a |
| inhibited | 0.8 | 240 | 4 | (a) | +45% | +0.149 | +0.003 [-0.004, +0.010] | -0.016 [-0.027, -0.004] | +0.146 [+0.129, +0.162] | +0.034 |
| inhibited | 0.8 | 240 | 4 | (b) | +11% | +0.099 | +0.032 [+0.027, +0.036] | +0.044 [+0.037, +0.052] | +0.093 [+0.082, +0.104] | +0.064 |
| inhibited | 0.8 | 240 | 4 | (c) | +63% | +0.000 | -0.060 [-0.066, -0.053] | -0.125 [-0.134, -0.115] | +0.010 [-0.005, +0.028] | -0.100 |
| inhibited | 0.8 | 240 | 4 | (d) 0.5 | +25% | +0.000 | -0.024 [-0.029, -0.019] | -0.033 [-0.041, -0.025] | +0.033 [+0.023, +0.044] | -0.047 |
| inhibited | 0.8 | 240 | 4 | (d) 0.8 | +39% | +0.000 | -0.041 [-0.047, -0.035] | -0.055 [-0.064, -0.045] | +0.047 [+0.035, +0.059] | -0.070 |
| inhibited | 0.8 | 240 | 4 | (e) | +10% | +0.000 | +0.001 [-0.010, +0.011] | -0.001 [-0.020, +0.018] | +0.008 [-0.020, +0.034] | n/a |
| inhibited | 0.8 | 240 | 2 | (a) | +45% | +0.111 | +0.025 [+0.019, +0.032] | +0.014 [+0.007, +0.022] | +0.108 [+0.098, +0.119] | +0.026 |
| inhibited | 0.8 | 240 | 2 | (b) | +11% | +0.074 | +0.040 [+0.035, +0.046] | +0.042 [+0.037, +0.049] | +0.071 [+0.064, +0.080] | +0.048 |
| inhibited | 0.8 | 240 | 2 | (c) | +63% | +0.000 | -0.048 [-0.053, -0.043] | -0.080 [-0.085, -0.074] | +0.002 [-0.005, +0.010] | -0.074 |
| inhibited | 0.8 | 240 | 2 | (d) 0.5 | +25% | +0.000 | -0.018 [-0.023, -0.014] | -0.028 [-0.033, -0.023] | +0.010 [+0.005, +0.016] | -0.035 |
| inhibited | 0.8 | 240 | 2 | (d) 0.8 | +39% | +0.000 | -0.028 [-0.033, -0.023] | -0.041 [-0.048, -0.035] | +0.018 [+0.012, +0.025] | -0.052 |
| inhibited | 0.8 | 240 | 2 | (e) | +10% | +0.000 | -0.000 [-0.009, +0.008] | -0.003 [-0.014, +0.006] | -0.003 [-0.015, +0.009] | n/a |
| inhibited | 0.6 | 240 | 4 | (a) | +45% | +0.145 | -0.023 [-0.029, -0.015] | -0.039 [-0.049, -0.027] | +0.133 [+0.113, +0.152] | +0.017 |
| inhibited | 0.6 | 240 | 4 | (b) | +11% | +0.097 | +0.018 [+0.013, +0.023] | +0.023 [+0.017, +0.031] | +0.088 [+0.076, +0.102] | +0.049 |
| inhibited | 0.6 | 240 | 4 | (c) | +63% | +0.000 | -0.075 [-0.082, -0.068] | -0.116 [-0.127, -0.106] | +0.006 [-0.014, +0.028] | -0.094 |
| inhibited | 0.6 | 240 | 4 | (d) 0.5 | +25% | +0.000 | -0.034 [-0.039, -0.029] | -0.037 [-0.044, -0.030] | +0.028 [+0.017, +0.040] | -0.045 |
| inhibited | 0.6 | 240 | 4 | (d) 0.8 | +39% | +0.000 | -0.055 [-0.060, -0.048] | -0.058 [-0.066, -0.049] | +0.038 [+0.024, +0.053] | -0.066 |
| inhibited | 0.6 | 240 | 4 | (e) | +10% | +0.000 | -0.002 [-0.012, +0.009] | +0.000 [-0.016, +0.016] | +0.009 [-0.021, +0.040] | n/a |
| inhibited | 0.6 | 240 | 2 | (a) | +45% | +0.109 | +0.010 [+0.003, +0.017] | +0.000 [-0.007, +0.009] | +0.104 [+0.093, +0.115] | +0.013 |
| inhibited | 0.6 | 240 | 2 | (b) | +11% | +0.074 | +0.030 [+0.025, +0.035] | +0.031 [+0.025, +0.037] | +0.069 [+0.061, +0.078] | +0.038 |
| inhibited | 0.6 | 240 | 2 | (c) | +63% | +0.000 | -0.053 [-0.058, -0.047] | -0.076 [-0.082, -0.069] | -0.003 [-0.011, +0.006] | -0.070 |
| inhibited | 0.6 | 240 | 2 | (d) 0.5 | +25% | +0.000 | -0.020 [-0.025, -0.016] | -0.027 [-0.032, -0.022] | +0.011 [+0.005, +0.017] | -0.033 |
| inhibited | 0.6 | 240 | 2 | (d) 0.8 | +39% | +0.000 | -0.031 [-0.036, -0.026] | -0.040 [-0.046, -0.034] | +0.018 [+0.011, +0.026] | -0.049 |
| inhibited | 0.6 | 240 | 2 | (e) | +10% | +0.000 | +0.002 [-0.007, +0.010] | +0.000 [-0.011, +0.011] | +0.002 [-0.014, +0.017] | n/a |
| inhibited | 0.8 | 300 | 4 | (a) | +44% | +0.148 | -0.003 [-0.009, +0.003] | -0.019 [-0.030, -0.009] | +0.164 [+0.147, +0.179] | +0.030 |
| inhibited | 0.8 | 300 | 4 | (b) | +11% | +0.099 | +0.030 [+0.026, +0.034] | +0.045 [+0.038, +0.053] | +0.099 [+0.088, +0.109] | +0.063 |
| inhibited | 0.8 | 300 | 4 | (c) | +61% | +0.000 | -0.061 [-0.067, -0.055] | -0.123 [-0.133, -0.113] | +0.022 [+0.002, +0.039] | -0.102 |
| inhibited | 0.8 | 300 | 4 | (d) 0.5 | +25% | +0.000 | -0.029 [-0.033, -0.024] | -0.040 [-0.048, -0.032] | +0.025 [+0.015, +0.036] | -0.048 |
| inhibited | 0.8 | 300 | 4 | (d) 0.8 | +40% | +0.000 | -0.045 [-0.050, -0.040] | -0.059 [-0.068, -0.050] | +0.048 [+0.035, +0.061] | -0.073 |
| inhibited | 0.8 | 300 | 4 | (e) | +11% | +0.000 | +0.003 [-0.007, +0.013] | -0.000 [-0.016, +0.017] | +0.015 [-0.011, +0.041] | n/a |
| inhibited | 0.8 | 300 | 2 | (a) | +44% | +0.112 | +0.018 [+0.013, +0.024] | +0.004 [-0.003, +0.011] | +0.102 [+0.093, +0.110] | +0.023 |
| inhibited | 0.8 | 300 | 2 | (b) | +11% | +0.074 | +0.037 [+0.032, +0.041] | +0.039 [+0.034, +0.044] | +0.068 [+0.062, +0.074] | +0.047 |
| inhibited | 0.8 | 300 | 2 | (c) | +61% | +0.000 | -0.047 [-0.052, -0.042] | -0.083 [-0.088, -0.077] | +0.003 [-0.006, +0.011] | -0.078 |
| inhibited | 0.8 | 300 | 2 | (d) 0.5 | +25% | +0.000 | -0.019 [-0.022, -0.016] | -0.030 [-0.034, -0.026] | +0.009 [+0.004, +0.014] | -0.037 |
| inhibited | 0.8 | 300 | 2 | (d) 0.8 | +40% | +0.000 | -0.027 [-0.032, -0.023] | -0.044 [-0.049, -0.039] | +0.019 [+0.013, +0.025] | -0.055 |
| inhibited | 0.8 | 300 | 2 | (e) | +11% | +0.000 | -0.003 [-0.011, +0.006] | -0.012 [-0.022, -0.002] | -0.015 [-0.028, -0.003] | n/a |
| inhibited | 0.6 | 400 | 4 | (a) | +44% | +0.152 | -0.034 [-0.039, -0.029] | -0.038 [-0.047, -0.029] | +0.179 [+0.154, +0.202] | +0.019 |
| inhibited | 0.6 | 400 | 4 | (b) | +11% | +0.103 | +0.013 [+0.009, +0.016] | +0.023 [+0.017, +0.030] | +0.107 [+0.093, +0.120] | +0.052 |
| inhibited | 0.6 | 400 | 4 | (c) | +61% | +0.000 | -0.078 [-0.083, -0.073] | -0.097 [-0.106, -0.088] | +0.060 [+0.032, +0.089] | -0.094 |
| inhibited | 0.6 | 400 | 4 | (d) 0.5 | +25% | +0.000 | -0.042 [-0.045, -0.038] | -0.039 [-0.045, -0.033] | +0.027 [+0.014, +0.040] | -0.046 |
| inhibited | 0.6 | 400 | 4 | (d) 0.8 | +40% | +0.000 | -0.065 [-0.068, -0.061] | -0.057 [-0.063, -0.049] | +0.046 [+0.029, +0.063] | -0.069 |
| inhibited | 0.6 | 400 | 4 | (e) | +9% | +0.000 | -0.011 [-0.020, -0.002] | -0.011 [-0.028, +0.006] | -0.004 [-0.047, +0.035] | n/a |
| inhibited | 0.6 | 400 | 2 | (a) | +44% | +0.118 | +0.011 [+0.006, +0.017] | +0.000 [-0.006, +0.007] | +0.117 [+0.107, +0.128] | +0.016 |
| inhibited | 0.6 | 400 | 2 | (b) | +11% | +0.078 | +0.029 [+0.025, +0.033] | +0.031 [+0.027, +0.036] | +0.075 [+0.067, +0.083] | +0.040 |
| inhibited | 0.6 | 400 | 2 | (c) | +61% | +0.000 | -0.041 [-0.046, -0.036] | -0.069 [-0.074, -0.062] | +0.015 [+0.006, +0.025] | -0.071 |
| inhibited | 0.6 | 400 | 2 | (d) 0.5 | +25% | +0.000 | -0.023 [-0.026, -0.019] | -0.032 [-0.036, -0.028] | +0.007 [+0.001, +0.013] | -0.035 |
| inhibited | 0.6 | 400 | 2 | (d) 0.8 | +40% | +0.000 | -0.034 [-0.038, -0.030] | -0.046 [-0.051, -0.042] | +0.012 [+0.005, +0.019] | -0.052 |
| inhibited | 0.6 | 400 | 2 | (e) | +9% | +0.000 | -0.003 [-0.010, +0.006] | -0.007 [-0.017, +0.003] | -0.011 [-0.027, +0.006] | n/a |
| clustered 4 m | 1.0 | 240 | 4 | (a) | +44% | +0.145 | +0.029 [+0.021, +0.037] | +0.017 [+0.007, +0.028] | +0.166 [+0.154, +0.178] | +0.042 |
| clustered 4 m | 1.0 | 240 | 4 | (b) | +11% | +0.095 | +0.048 [+0.044, +0.053] | +0.062 [+0.057, +0.068] | +0.098 [+0.090, +0.106] | +0.070 |
| clustered 4 m | 1.0 | 240 | 4 | (c) | +61% | +0.000 | -0.065 [-0.072, -0.058] | -0.131 [-0.140, -0.122] | +0.024 [+0.013, +0.036] | -0.105 |
| clustered 4 m | 1.0 | 240 | 4 | (d) 0.5 | +24% | +0.000 | +0.037 [+0.031, +0.042] | +0.048 [+0.041, +0.055] | +0.126 [+0.117, +0.135] | -0.048 |
| clustered 4 m | 1.0 | 240 | 4 | (d) 0.8 | +39% | +0.000 | +0.047 [+0.041, +0.054] | +0.062 [+0.054, +0.071] | +0.194 [+0.183, +0.204] | -0.073 |
| clustered 4 m | 1.0 | 240 | 4 | (e) | +8% | +0.000 | +0.064 [+0.052, +0.076] | +0.097 [+0.080, +0.114] | +0.116 [+0.096, +0.135] | n/a |
| clustered 4 m | 1.0 | 240 | 2 | (a) | +44% | +0.110 | +0.032 [+0.025, +0.039] | +0.023 [+0.016, +0.031] | +0.118 [+0.110, +0.127] | +0.033 |
| clustered 4 m | 1.0 | 240 | 2 | (b) | +11% | +0.073 | +0.048 [+0.043, +0.052] | +0.052 [+0.047, +0.057] | +0.074 [+0.068, +0.080] | +0.054 |
| clustered 4 m | 1.0 | 240 | 2 | (c) | +61% | +0.000 | -0.062 [-0.067, -0.057] | -0.094 [-0.099, -0.088] | +0.004 [-0.002, +0.009] | -0.079 |
| clustered 4 m | 1.0 | 240 | 2 | (d) 0.5 | +24% | +0.000 | +0.017 [+0.013, +0.022] | +0.015 [+0.011, +0.021] | +0.065 [+0.059, +0.071] | -0.036 |
| clustered 4 m | 1.0 | 240 | 2 | (d) 0.8 | +39% | +0.000 | +0.022 [+0.017, +0.028] | +0.020 [+0.013, +0.025] | +0.100 [+0.093, +0.107] | -0.055 |
| clustered 4 m | 1.0 | 240 | 2 | (e) | +8% | +0.000 | +0.021 [+0.012, +0.029] | +0.023 [+0.013, +0.033] | +0.026 [+0.014, +0.037] | n/a |
| clustered 4 m | 0.8 | 240 | 4 | (a) | +44% | +0.148 | +0.001 [-0.007, +0.009] | -0.014 [-0.025, -0.005] | +0.175 [+0.162, +0.188] | +0.029 |
| clustered 4 m | 0.8 | 240 | 4 | (b) | +11% | +0.096 | +0.037 [+0.032, +0.041] | +0.048 [+0.042, +0.054] | +0.102 [+0.093, +0.111] | +0.059 |
| clustered 4 m | 0.8 | 240 | 4 | (c) | +61% | +0.000 | -0.086 [-0.092, -0.079] | -0.150 [-0.158, -0.141] | +0.029 [+0.016, +0.042] | -0.102 |
| clustered 4 m | 0.8 | 240 | 4 | (d) 0.5 | +24% | +0.000 | +0.011 [+0.005, +0.017] | +0.017 [+0.009, +0.024] | +0.118 [+0.108, +0.127] | -0.048 |
| clustered 4 m | 0.8 | 240 | 4 | (d) 0.8 | +39% | +0.000 | +0.006 [-0.002, +0.013] | +0.012 [+0.002, +0.021] | +0.173 [+0.160, +0.184] | -0.072 |
| clustered 4 m | 0.8 | 240 | 4 | (e) | +8% | +0.000 | +0.056 [+0.044, +0.069] | +0.088 [+0.070, +0.105] | +0.127 [+0.102, +0.150] | n/a |
| clustered 4 m | 0.8 | 240 | 2 | (a) | +44% | +0.114 | +0.015 [+0.008, +0.022] | +0.006 [-0.002, +0.014] | +0.123 [+0.113, +0.134] | +0.024 |
| clustered 4 m | 0.8 | 240 | 2 | (b) | +11% | +0.073 | +0.041 [+0.036, +0.045] | +0.044 [+0.039, +0.050] | +0.078 [+0.071, +0.086] | +0.046 |
| clustered 4 m | 0.8 | 240 | 2 | (c) | +61% | +0.000 | -0.074 [-0.079, -0.069] | -0.103 [-0.108, -0.097] | +0.002 [-0.004, +0.009] | -0.077 |
| clustered 4 m | 0.8 | 240 | 2 | (d) 0.5 | +24% | +0.000 | +0.003 [-0.001, +0.008] | +0.001 [-0.004, +0.006] | +0.062 [+0.055, +0.069] | -0.036 |
| clustered 4 m | 0.8 | 240 | 2 | (d) 0.8 | +39% | +0.000 | +0.001 [-0.004, +0.007] | -0.002 [-0.008, +0.004] | +0.094 [+0.087, +0.102] | -0.054 |
| clustered 4 m | 0.8 | 240 | 2 | (e) | +8% | +0.000 | +0.018 [+0.009, +0.027] | +0.021 [+0.010, +0.031] | +0.027 [+0.014, +0.041] | n/a |
| clustered 4 m | 0.6 | 240 | 4 | (a) | +44% | +0.147 | -0.028 [-0.036, -0.020] | -0.046 [-0.056, -0.036] | +0.176 [+0.160, +0.192] | +0.015 |
| clustered 4 m | 0.6 | 240 | 4 | (b) | +11% | +0.095 | +0.022 [+0.017, +0.027] | +0.030 [+0.023, +0.036] | +0.104 [+0.093, +0.115] | +0.046 |
| clustered 4 m | 0.6 | 240 | 4 | (c) | +61% | +0.000 | -0.104 [-0.110, -0.099] | -0.160 [-0.168, -0.152] | +0.026 [+0.012, +0.042] | -0.094 |
| clustered 4 m | 0.6 | 240 | 4 | (d) 0.5 | +24% | +0.000 | -0.020 [-0.025, -0.014] | -0.019 [-0.026, -0.012] | +0.092 [+0.083, +0.103] | -0.045 |
| clustered 4 m | 0.6 | 240 | 4 | (d) 0.8 | +39% | +0.000 | -0.034 [-0.040, -0.027] | -0.033 [-0.041, -0.024] | +0.140 [+0.129, +0.152] | -0.067 |
| clustered 4 m | 0.6 | 240 | 4 | (e) | +8% | +0.000 | +0.046 [+0.033, +0.058] | +0.074 [+0.057, +0.091] | +0.142 [+0.111, +0.170] | n/a |
| clustered 4 m | 0.6 | 240 | 2 | (a) | +44% | +0.113 | -0.003 [-0.009, +0.005] | -0.011 [-0.018, -0.003] | +0.125 [+0.112, +0.137] | +0.012 |
| clustered 4 m | 0.6 | 240 | 2 | (b) | +11% | +0.072 | +0.031 [+0.026, +0.035] | +0.033 [+0.028, +0.038] | +0.081 [+0.072, +0.090] | +0.036 |
| clustered 4 m | 0.6 | 240 | 2 | (c) | +61% | +0.000 | -0.079 [-0.083, -0.074] | -0.102 [-0.107, -0.097] | +0.002 [-0.005, +0.010] | -0.072 |
| clustered 4 m | 0.6 | 240 | 2 | (d) 0.5 | +24% | +0.000 | -0.009 [-0.014, -0.004] | -0.011 [-0.016, -0.005] | +0.058 [+0.050, +0.065] | -0.034 |
| clustered 4 m | 0.6 | 240 | 2 | (d) 0.8 | +39% | +0.000 | -0.015 [-0.021, -0.009] | -0.018 [-0.025, -0.012] | +0.090 [+0.081, +0.099] | -0.051 |
| clustered 4 m | 0.6 | 240 | 2 | (e) | +8% | +0.000 | +0.012 [+0.003, +0.021] | +0.014 [+0.004, +0.025] | +0.022 [+0.006, +0.038] | n/a |
| clustered 4 m | 0.8 | 300 | 4 | (a) | +43% | +0.150 | +0.003 [-0.003, +0.009] | -0.013 [-0.022, -0.004] | +0.180 [+0.167, +0.193] | +0.033 |
| clustered 4 m | 0.8 | 300 | 4 | (b) | +11% | +0.102 | +0.041 [+0.037, +0.046] | +0.057 [+0.051, +0.064] | +0.118 [+0.108, +0.127] | +0.064 |
| clustered 4 m | 0.8 | 300 | 4 | (c) | +60% | +0.000 | -0.078 [-0.085, -0.072] | -0.149 [-0.158, -0.140] | +0.030 [+0.017, +0.044] | -0.101 |
| clustered 4 m | 0.8 | 300 | 4 | (d) 0.5 | +24% | +0.000 | +0.012 [+0.007, +0.018] | +0.019 [+0.012, +0.026] | +0.125 [+0.115, +0.134] | -0.048 |
| clustered 4 m | 0.8 | 300 | 4 | (d) 0.8 | +39% | +0.000 | +0.009 [+0.002, +0.015] | +0.017 [+0.007, +0.026] | +0.190 [+0.178, +0.200] | -0.072 |
| clustered 4 m | 0.8 | 300 | 4 | (e) | +11% | +0.000 | +0.061 [+0.049, +0.072] | +0.099 [+0.081, +0.116] | +0.143 [+0.119, +0.166] | n/a |
| clustered 4 m | 0.8 | 300 | 2 | (a) | +43% | +0.113 | +0.017 [+0.012, +0.023] | +0.008 [+0.002, +0.015] | +0.123 [+0.114, +0.132] | +0.025 |
| clustered 4 m | 0.8 | 300 | 2 | (b) | +11% | +0.077 | +0.042 [+0.038, +0.047] | +0.046 [+0.041, +0.051] | +0.081 [+0.074, +0.089] | +0.050 |
| clustered 4 m | 0.8 | 300 | 2 | (c) | +60% | +0.000 | -0.065 [-0.070, -0.061] | -0.098 [-0.103, -0.093] | +0.008 [+0.002, +0.015] | -0.077 |
| clustered 4 m | 0.8 | 300 | 2 | (d) 0.5 | +24% | +0.000 | +0.009 [+0.005, +0.014] | +0.007 [+0.002, +0.012] | +0.068 [+0.062, +0.075] | -0.036 |
| clustered 4 m | 0.8 | 300 | 2 | (d) 0.8 | +39% | +0.000 | +0.010 [+0.005, +0.016] | +0.007 [+0.001, +0.014] | +0.108 [+0.100, +0.117] | -0.055 |
| clustered 4 m | 0.8 | 300 | 2 | (e) | +11% | +0.000 | +0.023 [+0.014, +0.032] | +0.024 [+0.013, +0.035] | +0.030 [+0.016, +0.043] | n/a |
| clustered 4 m | 0.6 | 400 | 4 | (a) | +45% | +0.154 | -0.040 [-0.046, -0.035] | -0.063 [-0.072, -0.055] | +0.188 [+0.173, +0.202] | +0.018 |
| clustered 4 m | 0.6 | 400 | 4 | (b) | +11% | +0.101 | +0.018 [+0.014, +0.022] | +0.031 [+0.025, +0.036] | +0.117 [+0.106, +0.128] | +0.052 |
| clustered 4 m | 0.6 | 400 | 4 | (c) | +62% | +0.000 | -0.101 [-0.106, -0.095] | -0.165 [-0.174, -0.157] | +0.061 [+0.044, +0.077] | -0.097 |
| clustered 4 m | 0.6 | 400 | 4 | (d) 0.5 | +25% | +0.000 | -0.021 [-0.026, -0.016] | -0.019 [-0.026, -0.012] | +0.125 [+0.113, +0.137] | -0.047 |
| clustered 4 m | 0.6 | 400 | 4 | (d) 0.8 | +40% | +0.000 | -0.041 [-0.048, -0.036] | -0.039 [-0.048, -0.031] | +0.174 [+0.160, +0.188] | -0.069 |
| clustered 4 m | 0.6 | 400 | 4 | (e) | +9% | +0.000 | +0.028 [+0.017, +0.038] | +0.060 [+0.042, +0.077] | +0.130 [+0.094, +0.165] | n/a |
| clustered 4 m | 0.6 | 400 | 2 | (a) | +45% | +0.110 | -0.006 [-0.011, -0.000] | -0.018 [-0.024, -0.011] | +0.122 [+0.112, +0.132] | +0.011 |
| clustered 4 m | 0.6 | 400 | 2 | (b) | +11% | +0.072 | +0.027 [+0.023, +0.031] | +0.031 [+0.026, +0.035] | +0.079 [+0.072, +0.087] | +0.037 |
| clustered 4 m | 0.6 | 400 | 2 | (c) | +62% | +0.000 | -0.071 [-0.075, -0.066] | -0.103 [-0.108, -0.098] | +0.011 [+0.003, +0.020] | -0.073 |
| clustered 4 m | 0.6 | 400 | 2 | (d) 0.5 | +25% | +0.000 | -0.008 [-0.012, -0.004] | -0.011 [-0.015, -0.006] | +0.066 [+0.059, +0.073] | -0.036 |
| clustered 4 m | 0.6 | 400 | 2 | (d) 0.8 | +40% | +0.000 | -0.014 [-0.019, -0.010] | -0.018 [-0.023, -0.013] | +0.101 [+0.092, +0.109] | -0.052 |
| clustered 4 m | 0.6 | 400 | 2 | (e) | +9% | +0.000 | +0.019 [+0.010, +0.028] | +0.023 [+0.012, +0.034] | +0.037 [+0.019, +0.055] | n/a |
| clustered 8 m | 1.0 | 240 | 4 | (a) | +45% | +0.160 | +0.029 [+0.022, +0.036] | +0.017 [+0.005, +0.029] | +0.180 [+0.165, +0.196] | +0.053 |
| clustered 8 m | 1.0 | 240 | 4 | (b) | +12% | +0.105 | +0.046 [+0.042, +0.051] | +0.066 [+0.060, +0.073] | +0.105 [+0.097, +0.114] | +0.078 |
| clustered 8 m | 1.0 | 240 | 4 | (c) | +60% | +0.000 | -0.044 [-0.051, -0.037] | -0.119 [-0.129, -0.108] | +0.041 [+0.028, +0.055] | -0.103 |
| clustered 8 m | 1.0 | 240 | 4 | (d) 0.5 | +24% | +0.000 | +0.008 [+0.002, +0.013] | +0.011 [+0.003, +0.019] | +0.086 [+0.077, +0.095] | -0.047 |
| clustered 8 m | 1.0 | 240 | 4 | (d) 0.8 | +40% | +0.000 | -0.001 [-0.007, +0.005] | -0.001 [-0.011, +0.008] | +0.126 [+0.115, +0.138] | -0.074 |
| clustered 8 m | 1.0 | 240 | 4 | (e) | +11% | +0.000 | +0.045 [+0.033, +0.057] | +0.074 [+0.053, +0.091] | +0.099 [+0.075, +0.121] | n/a |
| clustered 8 m | 1.0 | 240 | 2 | (a) | +45% | +0.116 | +0.035 [+0.029, +0.041] | +0.023 [+0.016, +0.031] | +0.114 [+0.105, +0.123] | +0.038 |
| clustered 8 m | 1.0 | 240 | 2 | (b) | +12% | +0.078 | +0.049 [+0.044, +0.053] | +0.053 [+0.048, +0.058] | +0.076 [+0.070, +0.082] | +0.058 |
| clustered 8 m | 1.0 | 240 | 2 | (c) | +60% | +0.000 | -0.046 [-0.051, -0.040] | -0.083 [-0.088, -0.076] | +0.008 [+0.002, +0.014] | -0.077 |
| clustered 8 m | 1.0 | 240 | 2 | (d) 0.5 | +24% | +0.000 | -0.003 [-0.008, +0.001] | -0.011 [-0.016, -0.006] | +0.032 [+0.027, +0.037] | -0.035 |
| clustered 8 m | 1.0 | 240 | 2 | (d) 0.8 | +40% | +0.000 | -0.008 [-0.013, -0.003] | -0.021 [-0.027, -0.014] | +0.050 [+0.043, +0.056] | -0.055 |
| clustered 8 m | 1.0 | 240 | 2 | (e) | +11% | +0.000 | +0.026 [+0.016, +0.035] | +0.025 [+0.014, +0.037] | +0.029 [+0.017, +0.041] | n/a |
| clustered 8 m | 0.8 | 240 | 4 | (a) | +45% | +0.162 | +0.003 [-0.004, +0.011] | -0.013 [-0.025, -0.002] | +0.186 [+0.168, +0.203] | +0.039 |
| clustered 8 m | 0.8 | 240 | 4 | (b) | +12% | +0.106 | +0.037 [+0.032, +0.041] | +0.052 [+0.045, +0.058] | +0.114 [+0.104, +0.124] | +0.067 |
| clustered 8 m | 0.8 | 240 | 4 | (c) | +60% | +0.000 | -0.064 [-0.072, -0.057] | -0.129 [-0.140, -0.118] | +0.045 [+0.028, +0.061] | -0.100 |
| clustered 8 m | 0.8 | 240 | 4 | (d) 0.5 | +24% | +0.000 | -0.009 [-0.014, -0.004] | -0.009 [-0.017, -0.001] | +0.081 [+0.071, +0.091] | -0.047 |
| clustered 8 m | 0.8 | 240 | 4 | (d) 0.8 | +40% | +0.000 | -0.027 [-0.033, -0.021] | -0.031 [-0.040, -0.021] | +0.115 [+0.102, +0.127] | -0.072 |
| clustered 8 m | 0.8 | 240 | 4 | (e) | +11% | +0.000 | +0.040 [+0.028, +0.052] | +0.067 [+0.047, +0.086] | +0.114 [+0.083, +0.142] | n/a |
| clustered 8 m | 0.8 | 240 | 2 | (a) | +45% | +0.118 | +0.020 [+0.013, +0.027] | +0.009 [+0.001, +0.017] | +0.115 [+0.106, +0.126] | +0.028 |
| clustered 8 m | 0.8 | 240 | 2 | (b) | +12% | +0.078 | +0.040 [+0.035, +0.045] | +0.043 [+0.037, +0.048] | +0.076 [+0.069, +0.084] | +0.050 |
| clustered 8 m | 0.8 | 240 | 2 | (c) | +60% | +0.000 | -0.054 [-0.060, -0.049] | -0.086 [-0.092, -0.079] | +0.006 [-0.000, +0.014] | -0.075 |
| clustered 8 m | 0.8 | 240 | 2 | (d) 0.5 | +24% | +0.000 | -0.011 [-0.015, -0.006] | -0.018 [-0.023, -0.012] | +0.030 [+0.024, +0.035] | -0.035 |
| clustered 8 m | 0.8 | 240 | 2 | (d) 0.8 | +40% | +0.000 | -0.019 [-0.024, -0.014] | -0.029 [-0.036, -0.023] | +0.048 [+0.041, +0.055] | -0.054 |
| clustered 8 m | 0.8 | 240 | 2 | (e) | +11% | +0.000 | +0.023 [+0.013, +0.034] | +0.024 [+0.012, +0.036] | +0.032 [+0.017, +0.047] | n/a |
| clustered 8 m | 0.6 | 240 | 4 | (a) | +45% | +0.166 | -0.025 [-0.032, -0.019] | -0.042 [-0.052, -0.033] | +0.174 [+0.155, +0.192] | +0.027 |
| clustered 8 m | 0.6 | 240 | 4 | (b) | +12% | +0.108 | +0.021 [+0.017, +0.026] | +0.030 [+0.023, +0.037] | +0.113 [+0.101, +0.125] | +0.055 |
| clustered 8 m | 0.6 | 240 | 4 | (c) | +60% | +0.000 | -0.084 [-0.090, -0.077] | -0.132 [-0.142, -0.122] | +0.029 [+0.010, +0.049] | -0.092 |
| clustered 8 m | 0.6 | 240 | 4 | (d) 0.5 | +24% | +0.000 | -0.028 [-0.033, -0.022] | -0.027 [-0.035, -0.019] | +0.066 [+0.054, +0.079] | -0.043 |
| clustered 8 m | 0.6 | 240 | 4 | (d) 0.8 | +40% | +0.000 | -0.050 [-0.057, -0.044] | -0.051 [-0.060, -0.042] | +0.094 [+0.081, +0.109] | -0.067 |
| clustered 8 m | 0.6 | 240 | 4 | (e) | +11% | +0.000 | +0.034 [+0.021, +0.046] | +0.057 [+0.039, +0.075] | +0.136 [+0.097, +0.173] | n/a |
| clustered 8 m | 0.6 | 240 | 2 | (a) | +45% | +0.124 | +0.008 [+0.002, +0.015] | -0.001 [-0.008, +0.007] | +0.120 [+0.108, +0.133] | +0.021 |
| clustered 8 m | 0.6 | 240 | 2 | (b) | +12% | +0.082 | +0.033 [+0.027, +0.038] | +0.034 [+0.029, +0.041] | +0.080 [+0.071, +0.089] | +0.043 |
| clustered 8 m | 0.6 | 240 | 2 | (c) | +60% | +0.000 | -0.058 [-0.063, -0.052] | -0.081 [-0.087, -0.074] | +0.005 [-0.004, +0.014] | -0.069 |
| clustered 8 m | 0.6 | 240 | 2 | (d) 0.5 | +24% | +0.000 | -0.017 [-0.021, -0.012] | -0.022 [-0.027, -0.017] | +0.028 [+0.021, +0.034] | -0.032 |
| clustered 8 m | 0.6 | 240 | 2 | (d) 0.8 | +40% | +0.000 | -0.026 [-0.031, -0.020] | -0.033 [-0.039, -0.027] | +0.048 [+0.039, +0.056] | -0.050 |
| clustered 8 m | 0.6 | 240 | 2 | (e) | +11% | +0.000 | +0.021 [+0.012, +0.031] | +0.022 [+0.011, +0.033] | +0.037 [+0.021, +0.054] | n/a |
| clustered 8 m | 0.8 | 300 | 4 | (a) | +45% | +0.145 | -0.008 [-0.014, -0.001] | -0.030 [-0.039, -0.020] | +0.177 [+0.162, +0.192] | +0.024 |
| clustered 8 m | 0.8 | 300 | 4 | (b) | +11% | +0.097 | +0.029 [+0.025, +0.033] | +0.044 [+0.038, +0.051] | +0.104 [+0.094, +0.114] | +0.060 |
| clustered 8 m | 0.8 | 300 | 4 | (c) | +62% | +0.000 | -0.072 [-0.078, -0.065] | -0.145 [-0.155, -0.134] | +0.043 [+0.027, +0.059] | -0.106 |
| clustered 8 m | 0.8 | 300 | 4 | (d) 0.5 | +25% | +0.000 | -0.015 [-0.020, -0.010] | -0.018 [-0.025, -0.010] | +0.079 [+0.069, +0.089] | -0.051 |
| clustered 8 m | 0.8 | 300 | 4 | (d) 0.8 | +40% | +0.000 | -0.028 [-0.034, -0.022] | -0.031 [-0.041, -0.021] | +0.126 [+0.113, +0.139] | -0.075 |
| clustered 8 m | 0.8 | 300 | 4 | (e) | +11% | +0.000 | +0.045 [+0.035, +0.056] | +0.086 [+0.067, +0.106] | +0.142 [+0.113, +0.168] | n/a |
| clustered 8 m | 0.8 | 300 | 2 | (a) | +45% | +0.108 | +0.013 [+0.007, +0.019] | -0.001 [-0.007, +0.006] | +0.109 [+0.100, +0.118] | +0.017 |
| clustered 8 m | 0.8 | 300 | 2 | (b) | +11% | +0.070 | +0.032 [+0.028, +0.036] | +0.034 [+0.030, +0.039] | +0.066 [+0.060, +0.072] | +0.042 |
| clustered 8 m | 0.8 | 300 | 2 | (c) | +62% | +0.000 | -0.054 [-0.059, -0.048] | -0.089 [-0.095, -0.082] | +0.011 [+0.003, +0.020] | -0.080 |
| clustered 8 m | 0.8 | 300 | 2 | (d) 0.5 | +25% | +0.000 | -0.010 [-0.014, -0.006] | -0.018 [-0.023, -0.013] | +0.034 [+0.029, +0.040] | -0.038 |
| clustered 8 m | 0.8 | 300 | 2 | (d) 0.8 | +40% | +0.000 | -0.018 [-0.023, -0.012] | -0.029 [-0.036, -0.023] | +0.053 [+0.045, +0.060] | -0.057 |
| clustered 8 m | 0.8 | 300 | 2 | (e) | +11% | +0.000 | +0.022 [+0.013, +0.032] | +0.024 [+0.012, +0.035] | +0.031 [+0.017, +0.045] | n/a |
| clustered 8 m | 0.6 | 400 | 4 | (a) | +44% | +0.157 | -0.038 [-0.043, -0.033] | -0.050 [-0.058, -0.041] | +0.181 [+0.163, +0.199] | +0.021 |
| clustered 8 m | 0.6 | 400 | 4 | (b) | +11% | +0.104 | +0.012 [+0.009, +0.016] | +0.023 [+0.017, +0.030] | +0.111 [+0.100, +0.123] | +0.052 |
| clustered 8 m | 0.6 | 400 | 4 | (c) | +61% | +0.000 | -0.088 [-0.093, -0.083] | -0.130 [-0.138, -0.121] | +0.039 [+0.018, +0.061] | -0.093 |
| clustered 8 m | 0.6 | 400 | 4 | (d) 0.5 | +25% | +0.000 | -0.035 [-0.040, -0.031] | -0.032 [-0.039, -0.026] | +0.070 [+0.057, +0.083] | -0.045 |
| clustered 8 m | 0.6 | 400 | 4 | (d) 0.8 | +40% | +0.000 | -0.059 [-0.064, -0.054] | -0.055 [-0.063, -0.048] | +0.102 [+0.085, +0.117] | -0.068 |
| clustered 8 m | 0.6 | 400 | 4 | (e) | +10% | +0.000 | +0.027 [+0.018, +0.037] | +0.057 [+0.041, +0.074] | +0.146 [+0.109, +0.180] | n/a |
| clustered 8 m | 0.6 | 400 | 2 | (a) | +44% | +0.119 | +0.003 [-0.002, +0.008] | -0.008 [-0.014, -0.002] | +0.118 [+0.108, +0.128] | +0.017 |
| clustered 8 m | 0.6 | 400 | 2 | (b) | +11% | +0.079 | +0.027 [+0.024, +0.031] | +0.030 [+0.026, +0.035] | +0.076 [+0.069, +0.083] | +0.041 |
| clustered 8 m | 0.6 | 400 | 2 | (c) | +61% | +0.000 | -0.052 [-0.056, -0.048] | -0.081 [-0.086, -0.076] | +0.014 [+0.006, +0.023] | -0.070 |
| clustered 8 m | 0.6 | 400 | 2 | (d) 0.5 | +25% | +0.000 | -0.019 [-0.023, -0.016] | -0.026 [-0.030, -0.022] | +0.025 [+0.019, +0.032] | -0.034 |
| clustered 8 m | 0.6 | 400 | 2 | (d) 0.8 | +40% | +0.000 | -0.030 [-0.034, -0.026] | -0.040 [-0.045, -0.035] | +0.041 [+0.034, +0.049] | -0.051 |
| clustered 8 m | 0.6 | 400 | 2 | (e) | +10% | +0.000 | +0.012 [+0.003, +0.020] | +0.011 [-0.000, +0.023] | +0.019 [+0.000, +0.037] | n/a |

### Table 8. Detectors without skill on the reference by setting

Complete reference. Uniform: s 0, f 1. Unmapped only: 0.8 of the trees
that are not reference stems, f 0.3 (at p = 1 it holds commission only).
Displaced: 0.8 of all trees, each 5 to 10 m from its tree, f 0.3.

| Pattern | p | Trees/ha | r (m) | Uniform: corrected recall | Uniform: corrected F1 | Unmapped only: corrected recall | Unmapped only: corrected F1 | Displaced: corrected recall | Displaced: corrected F1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| inhibited | 1.0 | 240 | 4 | +0.002 [-0.017, +0.021] | +0.002 [-0.014, +0.019] | +0.003 [-0.005, +0.012] | +0.005 [-0.008, +0.020] | +0.002 [-0.016, +0.022] | -0.003 [-0.018, +0.012] |
| inhibited | 1.0 | 240 | 2 | +0.008 [-0.001, +0.017] | +0.007 [-0.002, +0.016] | +0.005 [-0.000, +0.011] | +0.008 [-0.000, +0.016] | -0.004 [-0.014, +0.007] | -0.005 [-0.014, +0.004] |
| inhibited | 0.8 | 240 | 4 | -0.007 [-0.027, +0.015] | -0.003 [-0.018, +0.013] | -0.007 [-0.020, +0.006] | -0.010 [-0.027, +0.007] | +0.001 [-0.022, +0.025] | -0.003 [-0.018, +0.012] |
| inhibited | 0.8 | 240 | 2 | +0.003 [-0.007, +0.014] | +0.002 [-0.006, +0.011] | -0.003 [-0.010, +0.004] | -0.004 [-0.013, +0.005] | +0.001 [-0.011, +0.011] | -0.001 [-0.010, +0.007] |
| inhibited | 0.6 | 240 | 4 | -0.004 [-0.028, +0.020] | -0.003 [-0.016, +0.010] | -0.012 [-0.032, +0.008] | -0.014 [-0.030, +0.004] | +0.004 [-0.022, +0.031] | -0.002 [-0.015, +0.011] |
| inhibited | 0.6 | 240 | 2 | -0.003 [-0.014, +0.010] | -0.002 [-0.010, +0.006] | -0.013 [-0.024, -0.003] | -0.014 [-0.023, -0.004] | -0.001 [-0.014, +0.013] | -0.002 [-0.010, +0.007] |
| inhibited | 0.8 | 300 | 4 | -0.001 [-0.023, +0.019] | -0.003 [-0.018, +0.010] | -0.009 [-0.022, +0.003] | -0.014 [-0.030, +0.003] | +0.014 [-0.010, +0.035] | -0.003 [-0.017, +0.010] |
| inhibited | 0.8 | 300 | 2 | +0.006 [-0.005, +0.017] | +0.003 [-0.006, +0.013] | -0.013 [-0.020, -0.006] | -0.017 [-0.026, -0.008] | -0.009 [-0.020, +0.002] | -0.008 [-0.016, +0.000] |
| inhibited | 0.6 | 400 | 4 | +0.009 [-0.022, +0.039] | +0.009 [-0.004, +0.021] | -0.043 [-0.061, -0.024] | -0.035 [-0.049, -0.020] | +0.005 [-0.027, +0.035] | -0.002 [-0.014, +0.008] |
| inhibited | 0.6 | 400 | 2 | +0.010 [-0.005, +0.023] | +0.006 [-0.003, +0.015] | -0.042 [-0.052, -0.032] | -0.038 [-0.047, -0.029] | -0.001 [-0.016, +0.014] | -0.000 [-0.009, +0.009] |
| clustered 4 m | 1.0 | 240 | 4 | -0.007 [-0.023, +0.008] | -0.009 [-0.022, +0.005] | +0.006 [-0.002, +0.013] | +0.008 [-0.004, +0.019] | +0.109 [+0.091, +0.127] | +0.089 [+0.072, +0.104] |
| clustered 4 m | 1.0 | 240 | 2 | -0.001 [-0.009, +0.008] | -0.001 [-0.008, +0.008] | +0.001 [-0.004, +0.005] | +0.001 [-0.006, +0.008] | +0.025 [+0.015, +0.035] | +0.022 [+0.014, +0.032] |
| clustered 4 m | 0.8 | 240 | 4 | -0.005 [-0.023, +0.013] | -0.007 [-0.022, +0.007] | +0.135 [+0.122, +0.149] | +0.167 [+0.153, +0.183] | +0.121 [+0.097, +0.144] | +0.081 [+0.063, +0.097] |
| clustered 4 m | 0.8 | 240 | 2 | -0.002 [-0.012, +0.008] | -0.002 [-0.010, +0.007] | +0.080 [+0.071, +0.090] | +0.100 [+0.089, +0.113] | +0.025 [+0.013, +0.038] | +0.020 [+0.010, +0.030] |
| clustered 4 m | 0.6 | 240 | 4 | -0.005 [-0.028, +0.019] | -0.006 [-0.019, +0.008] | +0.310 [+0.290, +0.332] | +0.277 [+0.261, +0.294] | +0.137 [+0.109, +0.165] | +0.068 [+0.053, +0.084] |
| clustered 4 m | 0.6 | 240 | 2 | +0.003 [-0.009, +0.016] | +0.002 [-0.007, +0.010] | +0.161 [+0.148, +0.178] | +0.152 [+0.140, +0.167] | +0.025 [+0.011, +0.041] | +0.016 [+0.006, +0.026] |
| clustered 4 m | 0.8 | 300 | 4 | -0.025 [-0.040, -0.009] | -0.019 [-0.030, -0.007] | +0.115 [+0.105, +0.128] | +0.148 [+0.135, +0.162] | +0.118 [+0.097, +0.138] | +0.080 [+0.065, +0.095] |
| clustered 4 m | 0.8 | 300 | 2 | -0.005 [-0.014, +0.004] | -0.005 [-0.012, +0.003] | +0.068 [+0.061, +0.076] | +0.087 [+0.078, +0.097] | +0.024 [+0.013, +0.036] | +0.020 [+0.010, +0.028] |
| clustered 4 m | 0.6 | 400 | 4 | +0.005 [-0.016, +0.028] | +0.001 [-0.010, +0.013] | +0.261 [+0.245, +0.279] | +0.238 [+0.224, +0.252] | +0.135 [+0.104, +0.165] | +0.061 [+0.047, +0.075] |
| clustered 4 m | 0.6 | 400 | 2 | -0.003 [-0.015, +0.007] | -0.002 [-0.010, +0.005] | +0.144 [+0.133, +0.156] | +0.136 [+0.126, +0.147] | +0.034 [+0.019, +0.049] | +0.020 [+0.011, +0.029] |
| clustered 8 m | 1.0 | 240 | 4 | +0.024 [+0.005, +0.041] | +0.023 [+0.007, +0.038] | +0.003 [-0.004, +0.010] | +0.004 [-0.006, +0.017] | +0.123 [+0.103, +0.142] | +0.096 [+0.081, +0.111] |
| clustered 8 m | 1.0 | 240 | 2 | +0.008 [-0.001, +0.017] | +0.007 [-0.002, +0.016] | +0.000 [-0.005, +0.005] | -0.000 [-0.008, +0.007] | +0.037 [+0.027, +0.047] | +0.032 [+0.023, +0.042] |
| clustered 8 m | 0.8 | 240 | 4 | +0.027 [+0.005, +0.049] | +0.020 [+0.004, +0.036] | +0.045 [+0.033, +0.057] | +0.060 [+0.046, +0.075] | +0.142 [+0.118, +0.164] | +0.087 [+0.073, +0.102] |
| clustered 8 m | 0.8 | 240 | 2 | +0.009 [-0.002, +0.020] | +0.007 [-0.002, +0.016] | +0.023 [+0.015, +0.030] | +0.029 [+0.018, +0.038] | +0.041 [+0.030, +0.053] | +0.030 [+0.022, +0.040] |
| clustered 8 m | 0.6 | 240 | 4 | +0.015 [-0.015, +0.043] | +0.008 [-0.008, +0.024] | +0.105 [+0.086, +0.124] | +0.095 [+0.079, +0.112] | +0.151 [+0.123, +0.177] | +0.066 [+0.052, +0.078] |
| clustered 8 m | 0.6 | 240 | 2 | +0.005 [-0.008, +0.017] | +0.003 [-0.006, +0.011] | +0.046 [+0.035, +0.056] | +0.043 [+0.032, +0.052] | +0.042 [+0.030, +0.055] | +0.025 [+0.017, +0.034] |
| clustered 8 m | 0.8 | 300 | 4 | -0.000 [-0.019, +0.020] | -0.001 [-0.013, +0.014] | +0.044 [+0.033, +0.055] | +0.055 [+0.041, +0.069] | +0.141 [+0.119, +0.164] | +0.086 [+0.071, +0.100] |
| clustered 8 m | 0.8 | 300 | 2 | +0.007 [-0.004, +0.017] | +0.006 [-0.004, +0.015] | +0.018 [+0.010, +0.025] | +0.023 [+0.014, +0.032] | +0.038 [+0.027, +0.049] | +0.029 [+0.021, +0.038] |
| clustered 8 m | 0.6 | 400 | 4 | +0.003 [-0.023, +0.028] | -0.005 [-0.018, +0.007] | +0.101 [+0.084, +0.119] | +0.087 [+0.073, +0.103] | +0.149 [+0.120, +0.177] | +0.052 [+0.039, +0.065] |
| clustered 8 m | 0.6 | 400 | 2 | +0.024 [+0.012, +0.036] | +0.015 [+0.007, +0.023] | +0.038 [+0.028, +0.048] | +0.035 [+0.027, +0.044] | +0.043 [+0.027, +0.058] | +0.026 [+0.017, +0.036] |

### Table 9. Leads on the complete and on the half reference

Each cell gives the complete-reference value, then the half-reference
value, with the half-reference interval where shown. (d) 0.5 and (d) 0.8:
the baseline with split crowns at rate 0.5 and 0.8, over the baseline.

| Pattern | p | Trees/ha | r (m) | (b) observed F1 lead | (b) corrected F1 lead [half: 95% CI] | (b) corrected recall lead | (a) corrected F1 lead [half: 95% CI] | (c) corrected F1 lead | (d) 0.5 corrected F1 lead [half: 95% CI] | (d) 0.8 corrected F1 lead [half: 95% CI] | Baseline corrected recall - truth |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| inhibited | 1.0 | 240 | 4 | +0.041 → +0.020 | +0.060 → +0.025 [+0.019, +0.032] | +0.091 → +0.090 | +0.009 → -0.019 [-0.028, -0.009] | -0.119 → -0.079 | -0.028 → -0.022 [-0.028, -0.016] | -0.047 → -0.036 [-0.043, -0.029] | -0.127 → -0.127 |
| inhibited | 1.0 | 240 | 2 | +0.046 → +0.024 | +0.050 → +0.025 [+0.020, +0.030] | +0.069 → +0.066 | +0.024 → -0.003 [-0.010, +0.005] | -0.082 → -0.066 | -0.025 → -0.023 [-0.027, -0.018] | -0.039 → -0.034 [-0.040, -0.028] | -0.038 → -0.036 |
| inhibited | 0.8 | 240 | 4 | +0.032 → +0.014 | +0.044 → +0.019 [+0.012, +0.026] | +0.093 → +0.094 | -0.016 → -0.024 [-0.033, -0.013] | -0.125 → -0.073 | -0.033 → -0.023 [-0.029, -0.017] | -0.055 → -0.035 [-0.042, -0.028] | -0.105 → -0.107 |
| inhibited | 0.8 | 240 | 2 | +0.040 → +0.021 | +0.042 → +0.022 [+0.016, +0.028] | +0.071 → +0.070 | +0.014 → -0.005 [-0.012, +0.004] | -0.080 → -0.059 | -0.028 → -0.023 [-0.027, -0.018] | -0.041 → -0.032 [-0.038, -0.027] | -0.035 → -0.030 |
| inhibited | 0.6 | 240 | 4 | +0.018 → +0.004 | +0.023 → +0.007 [+0.001, +0.014] | +0.088 → +0.087 | -0.039 → -0.033 [-0.041, -0.024] | -0.116 → -0.066 | -0.037 → -0.024 [-0.028, -0.018] | -0.058 → -0.035 [-0.041, -0.028] | -0.078 → -0.073 |
| inhibited | 0.6 | 240 | 2 | +0.030 → +0.013 | +0.031 → +0.014 [+0.008, +0.019] | +0.069 → +0.066 | +0.000 → -0.012 [-0.019, -0.004] | -0.076 → -0.052 | -0.027 → -0.020 [-0.024, -0.016] | -0.040 → -0.029 [-0.034, -0.024] | -0.033 → -0.022 |
| inhibited | 0.8 | 300 | 4 | +0.030 → +0.015 | +0.045 → +0.022 [+0.016, +0.029] | +0.099 → +0.114 | -0.019 → -0.018 [-0.027, -0.009] | -0.123 → -0.069 | -0.040 → -0.023 [-0.029, -0.017] | -0.059 → -0.036 [-0.043, -0.029] | -0.141 → -0.139 |
| inhibited | 0.8 | 300 | 2 | +0.037 → +0.021 | +0.039 → +0.022 [+0.017, +0.027] | +0.068 → +0.073 | +0.004 → -0.006 [-0.013, +0.001] | -0.083 → -0.058 | -0.030 → -0.025 [-0.028, -0.021] | -0.044 → -0.033 [-0.038, -0.028] | -0.053 → -0.051 |
| inhibited | 0.6 | 400 | 4 | +0.013 → +0.003 | +0.023 → +0.010 [+0.005, +0.015] | +0.107 → +0.114 | -0.038 → -0.021 [-0.028, -0.014] | -0.097 → -0.046 | -0.039 → -0.018 [-0.023, -0.014] | -0.057 → -0.025 [-0.031, -0.019] | -0.136 → -0.142 |
| inhibited | 0.6 | 400 | 2 | +0.029 → +0.013 | +0.031 → +0.014 [+0.010, +0.018] | +0.075 → +0.072 | +0.000 → -0.008 [-0.014, -0.003] | -0.069 → -0.045 | -0.032 → -0.024 [-0.027, -0.021] | -0.046 → -0.032 [-0.036, -0.028] | -0.062 → -0.064 |
| clustered 4 m | 1.0 | 240 | 4 | +0.048 → +0.023 | +0.062 → +0.029 [+0.023, +0.035] | +0.098 → +0.098 | +0.017 → -0.016 [-0.025, -0.007] | -0.131 → -0.104 | +0.048 → +0.013 [+0.005, +0.019] | +0.062 → +0.016 [+0.008, +0.025] | -0.007 → +0.010 |
| clustered 4 m | 1.0 | 240 | 2 | +0.048 → +0.027 | +0.052 → +0.028 [+0.023, +0.034] | +0.074 → +0.074 | +0.023 → -0.002 [-0.009, +0.005] | -0.094 → -0.076 | +0.015 → -0.001 [-0.005, +0.003] | +0.020 → +0.000 [-0.005, +0.006] | +0.019 → +0.024 |
| clustered 4 m | 0.8 | 240 | 4 | +0.037 → +0.016 | +0.048 → +0.020 [+0.015, +0.026] | +0.102 → +0.103 | -0.014 → -0.028 [-0.036, -0.019] | -0.150 → -0.108 | +0.017 → -0.005 [-0.012, +0.001] | +0.012 → -0.012 [-0.020, -0.004] | +0.059 → +0.077 |
| clustered 4 m | 0.8 | 240 | 2 | +0.041 → +0.020 | +0.044 → +0.022 [+0.017, +0.027] | +0.078 → +0.076 | +0.006 → -0.009 [-0.016, -0.002] | -0.103 → -0.075 | +0.001 → -0.009 [-0.013, -0.004] | -0.002 → -0.010 [-0.016, -0.005] | +0.055 → +0.061 |
| clustered 4 m | 0.6 | 240 | 4 | +0.022 → +0.008 | +0.030 → +0.013 [+0.007, +0.018] | +0.104 → +0.107 | -0.046 → -0.036 [-0.044, -0.029] | -0.160 → -0.101 | -0.019 → -0.020 [-0.025, -0.015] | -0.033 → -0.028 [-0.035, -0.021] | +0.131 → +0.143 |
| clustered 4 m | 0.6 | 240 | 2 | +0.031 → +0.013 | +0.033 → +0.014 [+0.010, +0.019] | +0.081 → +0.077 | -0.011 → -0.018 [-0.024, -0.011] | -0.102 → -0.071 | -0.011 → -0.014 [-0.019, -0.009] | -0.018 → -0.018 [-0.023, -0.012] | +0.084 → +0.088 |
| clustered 4 m | 0.8 | 300 | 4 | +0.041 → +0.018 | +0.057 → +0.024 [+0.017, +0.030] | +0.118 → +0.117 | -0.013 → -0.031 [-0.039, -0.022] | -0.149 → -0.105 | +0.019 → -0.002 [-0.009, +0.004] | +0.017 → -0.012 [-0.019, -0.004] | +0.040 → +0.059 |
| clustered 4 m | 0.8 | 300 | 2 | +0.042 → +0.022 | +0.046 → +0.023 [+0.018, +0.029] | +0.081 → +0.082 | +0.008 → -0.012 [-0.019, -0.006] | -0.098 → -0.077 | +0.007 → -0.005 [-0.010, -0.001] | +0.007 → -0.012 [-0.018, -0.006] | +0.037 → +0.046 |
| clustered 4 m | 0.6 | 400 | 4 | +0.018 → +0.007 | +0.031 → +0.014 [+0.009, +0.019] | +0.117 → +0.123 | -0.063 → -0.041 [-0.049, -0.034] | -0.165 → -0.094 | -0.019 → -0.015 [-0.020, -0.009] | -0.039 → -0.027 [-0.034, -0.021] | +0.106 → +0.115 |
| clustered 4 m | 0.6 | 400 | 2 | +0.027 → +0.013 | +0.031 → +0.015 [+0.011, +0.019] | +0.079 → +0.079 | -0.018 → -0.020 [-0.026, -0.015] | -0.103 → -0.070 | -0.011 → -0.014 [-0.018, -0.010] | -0.018 → -0.021 [-0.025, -0.017] | +0.065 → +0.066 |
| clustered 8 m | 1.0 | 240 | 4 | +0.046 → +0.019 | +0.066 → +0.024 [+0.017, +0.030] | +0.105 → +0.099 | +0.017 → -0.019 [-0.028, -0.010] | -0.119 → -0.089 | +0.011 → -0.008 [-0.014, -0.001] | -0.001 → -0.024 [-0.031, -0.017] | -0.073 → -0.058 |
| clustered 8 m | 1.0 | 240 | 2 | +0.049 → +0.025 | +0.053 → +0.026 [+0.020, +0.031] | +0.076 → +0.073 | +0.023 → -0.001 [-0.008, +0.006] | -0.083 → -0.064 | -0.011 → -0.014 [-0.019, -0.009] | -0.021 → -0.025 [-0.031, -0.020] | -0.021 → -0.022 |
| clustered 8 m | 0.8 | 240 | 4 | +0.037 → +0.012 | +0.052 → +0.016 [+0.009, +0.022] | +0.114 → +0.105 | -0.013 → -0.029 [-0.038, -0.020] | -0.129 → -0.086 | -0.009 → -0.015 [-0.021, -0.009] | -0.031 → -0.033 [-0.039, -0.026] | -0.033 → -0.020 |
| clustered 8 m | 0.8 | 240 | 2 | +0.040 → +0.018 | +0.043 → +0.018 [+0.013, +0.024] | +0.076 → +0.070 | +0.009 → -0.008 [-0.015, -0.001] | -0.086 → -0.060 | -0.018 → -0.019 [-0.024, -0.015] | -0.029 → -0.031 [-0.036, -0.026] | -0.006 → -0.003 |
| clustered 8 m | 0.6 | 240 | 4 | +0.021 → +0.005 | +0.030 → +0.008 [+0.003, +0.015] | +0.113 → +0.103 | -0.042 → -0.035 [-0.043, -0.028] | -0.132 → -0.077 | -0.027 → -0.019 [-0.025, -0.014] | -0.051 → -0.034 [-0.040, -0.028] | +0.013 → +0.019 |
| clustered 8 m | 0.6 | 240 | 2 | +0.033 → +0.014 | +0.034 → +0.014 [+0.009, +0.019] | +0.080 → +0.073 | -0.001 → -0.010 [-0.016, -0.004] | -0.081 → -0.053 | -0.022 → -0.019 [-0.023, -0.015] | -0.033 → -0.029 [-0.033, -0.024] | +0.009 → +0.008 |
| clustered 8 m | 0.8 | 300 | 4 | +0.029 → +0.007 | +0.044 → +0.012 [+0.007, +0.018] | +0.104 → +0.094 | -0.030 → -0.034 [-0.042, -0.026] | -0.145 → -0.090 | -0.018 → -0.019 [-0.025, -0.013] | -0.031 → -0.031 [-0.038, -0.024] | -0.048 → -0.034 |
| clustered 8 m | 0.8 | 300 | 2 | +0.032 → +0.015 | +0.034 → +0.016 [+0.011, +0.020] | +0.066 → +0.067 | -0.001 → -0.015 [-0.022, -0.008] | -0.089 → -0.068 | -0.018 → -0.018 [-0.023, -0.014] | -0.029 → -0.028 [-0.033, -0.023] | -0.021 → -0.013 |
| clustered 8 m | 0.6 | 400 | 4 | +0.012 → +0.001 | +0.023 → +0.008 [+0.003, +0.013] | +0.111 → +0.115 | -0.050 → -0.031 [-0.039, -0.024] | -0.130 → -0.067 | -0.032 → -0.019 [-0.024, -0.014] | -0.055 → -0.030 [-0.036, -0.025] | -0.034 → -0.022 |
| clustered 8 m | 0.6 | 400 | 2 | +0.027 → +0.012 | +0.030 → +0.013 [+0.009, +0.017] | +0.076 → +0.075 | -0.008 → -0.015 [-0.021, -0.010] | -0.081 → -0.055 | -0.026 → -0.020 [-0.024, -0.017] | -0.040 → -0.029 [-0.033, -0.024] | -0.009 → -0.003 |

### Table 10. Clustering of reference stems: benchmark and simulation

`reference_stem_clustering.R`. Benchmark: the 54 distributed plots of the
population (SJER has none), each in its 20 m core box, which NEON censuses
whole; the 52 tower plots are left out because which of their quadrants were
sampled cannot be read from the stems. Simulation: the four 20 m quadrants of
each core of scenario 4's plots, every tree mapped. Observed is the mean
number of other reference stems within d of a reference stem; random is the
same for as many stems placed at random in the same box; the ratio is
observed pairs over random pairs, and the excess is observed minus random,
each with a 95% interval from the same resamples of plots within sites
(patterns). Unlike the ratio, the excess does not fall as density rises for
clusters of a fixed size. Mapping a random 60% of the simulated trees changes
the ratios by 0.03 or less and scales the excess by 0.58–0.68. Keeping only
the windows with at least six stems, as the population's gate does, lowers
the ratios by up to 0.19 for the tight clusters and by 0.06 or less for the
other patterns, and changes the excess by up to +0.17 for the tight clusters
and by 0.03 or less for the others.

| Source | Plots | Stems | Stems/ha | Within 2 m: observed | Within 2 m: random | Within 2 m: ratio [95% CI] | Within 2 m: excess [95% CI] | Within 4 m: observed | Within 4 m: random | Within 4 m: ratio [95% CI] | Within 4 m: excess [95% CI] |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SOAP | 11 | 96 | 218 | 0.42 | 0.28 | 1.51 [1.18, 2.03] | +0.14 [+0.05, +0.24] | 1.12 | 1.01 | 1.12 [0.83, 1.56] | +0.12 [-0.19, +0.45] |
| TEAK | 13 | 168 | 323 | 0.68 | 0.44 | 1.56 [1.11, 2.02] | +0.24 [+0.04, +0.44] | 2.06 | 1.59 | 1.30 [1.11, 1.64] | +0.47 [+0.18, +0.85] |
| WREF | 18 | 378 | 525 | 1.20 | 1.01 | 1.19 [0.81, 1.48] | +0.19 [-0.12, +0.61] | 4.05 | 3.68 | 1.10 [0.95, 1.19] | +0.37 [-0.11, +0.85] |
| ABBY | 12 | 234 | 488 | 0.46 | 0.69 | 0.66 [0.31, 0.96] | -0.23 [-0.39, -0.03] | 2.93 | 2.53 | 1.16 [0.98, 1.37] | +0.40 [-0.03, +0.78] |
| Four sites | 54 | 876 | 406 | 0.82 | 0.73 | 1.11 [0.86, 1.34] | +0.08 [-0.08, +0.30] | 3.05 | 2.68 | 1.14 [1.06, 1.21] | +0.37 [+0.13, +0.63] |
| Inhibited, 240 trees/ha | 200 | 7562 | 236 | 0.12 | 0.27 | 0.46 [0.42, 0.50] | -0.15 [-0.16, -0.13] | 0.86 | 0.98 | 0.87 [0.85, 0.90] | -0.12 [-0.15, -0.10] |
| Inhibited, 400 trees/ha | 200 | 12811 | 400 | 0.21 | 0.46 | 0.45 [0.43, 0.47] | -0.25 [-0.26, -0.24] | 1.44 | 1.66 | 0.87 [0.85, 0.88] | -0.22 [-0.25, -0.19] |
| Loose clusters, 240 trees/ha | 200 | 7975 | 249 | 0.50 | 0.35 | 1.41 [1.34, 1.47] | +0.14 [+0.12, +0.17] | 1.71 | 1.30 | 1.32 [1.28, 1.36] | +0.41 [+0.36, +0.46] |
| Loose clusters, 400 trees/ha | 200 | 12536 | 392 | 0.63 | 0.51 | 1.24 [1.20, 1.28] | +0.12 [+0.10, +0.14] | 2.25 | 1.87 | 1.20 [1.18, 1.23] | +0.38 [+0.34, +0.43] |
| Tight clusters, 240 trees/ha | 200 | 7496 | 234 | 1.37 | 0.40 | 3.39 [3.25, 3.57] | +0.96 [+0.91, +1.02] | 4.00 | 1.47 | 2.72 [2.62, 2.83] | +2.53 [+2.39, +2.66] |
| Tight clusters, 400 trees/ha | 200 | 12550 | 392 | 1.53 | 0.58 | 2.65 [2.56, 2.76] | +0.95 [+0.91, +1.00] | 4.64 | 2.11 | 2.20 [2.13, 2.28] | +2.53 [+2.39, +2.66] |

## Reproduction

```sh
CLAUDE_JOB_DIR=<paper_runs> Rscript scripts/simulate_chance_correction.R \
  N=200 K=200 SEED=0 CORES=6
CLAUDE_JOB_DIR=<paper_runs> Rscript scripts/reference_stem_clustering.R
```

The first version's run took 7.7 minutes on 6 cores. With scenario 4 the run
took 54 minutes on 6 cores (7.5 for scenarios 1 to 3, 46 for scenario 4), and
with the split crowns 40 minutes on 8 cores (3.7 and 36.5); its outputs do not
depend on the number of cores; the clustering script
took 7 seconds on one core. Plot `D<trees/ha>_<i>` draws its trees,
reference quadrants, mapping draws and detector stream from seed
`seed_for("chance_sim", plot, "plot")`, and its shift k from
`seed_for("chance_sim", plot, "null") + k` (each plus SEED × 1000003, wrapped
to a valid seed); the clustered plots are `M4_D<trees/ha>_<i>` and
`M8_D<trees/ha>_<i>`, seeded the same way. The bootstrap uses the master
tables' 1,000 resamples and seed. The helpers are in
`chance_simulation_lib.R`, with unit tests in
`tests/testthat/test-chance-simulation.R`. The simulation writes, under
`sensitivity/chance_simulation/`, the per-plot counts
(`chance_simulation_cells.csv`), every detector's pooled scores
(`chance_simulation_detectors.csv`, including corrected precision and the
oracle scores), one CSV per table above (`chance_simulation_table1_single.csv`
to `chance_simulation_table4_zero_skill.csv`), the same for scenario 4
(`chance_simulation_structure_cells.csv`, `_structure_neighbours.csv`,
`_structure_detectors.csv`, `_structure_leads.csv` and
`chance_simulation_table5_structure_settings.csv` to
`chance_simulation_table9_structure_half.csv`), the generated tables
(`chance_simulation_tables.md`) and the settings with the result of the
scenario-2 check (`chance_simulation_settings.txt`). The output files hold no
wall time, core count or path, so two runs with the same N, K and SEED give
identical files; the extension left the files of scenarios 1 to 3
byte-identical. The clustering script writes `reference_clustering_plots.csv`
(one row per plot or simulated window and distance),
`reference_clustering_summary.csv` and `reference_clustering_tables.md` to the
same directory, reading only the sealed root's `population.csv` and
`population_stems.csv`.
