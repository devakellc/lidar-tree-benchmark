# Native-density performance does not predict sparse-density performance

Full title: Native-density performance does not predict sparse-density
performance: benchmarking classical and zero-shot deep tree detectors on
national-mapping airborne LiDAR with field-mapped stems.

Alex Grigoryev. Co-authors, affiliations and the corresponding address are to be
completed.

Draft manuscript for the ISPRS Journal of Photogrammetry and Remote Sensing.
Citations use the keys of the repository bibliography (`docs/references.bib`);
every number is taken from a committed study report, listed in the [draft
notes](README.md).

## Highlights

- Three zero-shot 3D segmenters and eight other detectors scored on 2,525 field
  stems.
- Deep segmenters lead a canopy-height baseline by only 0.05 F1 at 10 pulses/m².
- SegmentAnyTree holds to the QL2 floor of 2 pulses/m² and collapses below it.
- Native-density rank does not predict detector rank below the QL2 floor.
- Precision inside censused subplots is 0.08 to 0.34 above nominal-plot
  precision.

## Abstract

Deep 3D tree instance segmenters are trained and benchmarked on dense laser
scanning, while national mapping programmes such as the USGS 3D Elevation
Program deliver airborne laser scanning (ALS) at 2 to 8 pulses/m². We benchmark
three published segmenters used zero-shot (ForestFormer3D, SegmentAnyTree and
TreeisoNet), six classical detectors and two RGB detectors against 2,525
field-mapped stems in 106 plots at five NEON sites in California and Washington.
Every detector reads the same hash-sealed clips at native density (median 9.8
pulses/m²) and at five decimated densities down to 0.6 pulses/m², one of them at
the QL2 floor of 2 pulses/m². At native density the two best segmenters lead a
canopy-height-model variable-window baseline by 0.048 [0.028, 0.069] and 0.044
[0.021, 0.067] F1, and four other detectors are indistinguishable from it. The
response to density belongs to the individual model, not to its method family:
SegmentAnyTree holds to the QL2 floor and collapses below it (F1 0.495 at native
density, 0.128 at 0.6 pulses/m²), ForestFormer3D declines slowly and TreeisoNet
stays flat. The native-density ranking of eight detectors predicts their ranking
down to the QL2 floor (Spearman 0.71 [0.38, 0.81]) and not below it (−0.05
[−0.17, 0.26]). Scoring precision only inside censused subplots raises it by
0.08 to 0.34, so nominal-plot precision is a lower bound. Earlier, natively
sparse flights over the same plots show that decimation overstates recall by
0.03 to 0.05 for most detectors and by up to 0.19 for SegmentAnyTree. On the
dense FGI-EMIT benchmark the same checkpoints lead the baseline by 0.26 to 0.29
F1; thinning it to the NEON densities brings ForestFormer3D's lead down to the
NEON level only at about 11 pulses/m², so we report the two datasets as a
contrast, not as a density effect. The findings hold under alternative matchers,
stem-position jitter and replication in a second region. Clips, detections and
tables are archived with a one-command rebuild.

**Keywords:** individual tree detection; airborne laser scanning; point density;
deep learning; instance segmentation; benchmark; NEON; 3DEP

## 1. Introduction

Individual tree detection from airborne laser scanning (ALS) feeds forest
inventory, carbon accounting, fuel mapping and habitat models. The data that
most practitioners can obtain for a whole ownership or a whole state come from
national mapping programmes. The USGS 3D Elevation Program (3DEP) specifies an
aggregate nominal pulse density of at least 2 pulses/m² for quality level 2
(QL2) and at least 8 pulses/m² for quality level 1 (QL1) [@usgs2026topographic].
These are the densities at which tree detectors are deployed in practice.

Two literatures have grown around the task and they rarely meet. Classical
detectors, such as local maxima on a canopy height model (CHM) with a
height-dependent window [@popescu2004seeing], region growing in the point cloud
[@li2012new], multi-scale point segmentation [@vega2014ptrees] and adaptive mean
shift [@ferraz2016lidar], were developed and compared at 1 to 25 pulses/m²
[@kaartinen2012international; @jakubowski2013tradeoffs; @eysn2015benchmark;
@sparks2022crosscomparison]. Deep 3D instance segmenters
[@wielgosz2024segmentanytree; @xiang2025forestformer3d; @xi2025new] are trained
and benchmarked on unmanned, mobile and terrestrial laser scanning at hundreds
to thousands of points per square metre [@puliti2023forinstance;
@ruoppa2026benchmarking], and the sparsest conditions they are tested on are
subsampled dense scenes.

Whether the published checkpoints of these segmenters help at national-mapping
density is therefore an open question, and three obstacles stand in the way of
answering it. First, no instance labels exist at such densities, so the
reference has to be field-mapped stems, which are incomplete: plots are censused
in subplots, and a detection of a real but unmapped tree counts as an error.
Second, sparse acquisitions are usually simulated by decimating a dense one, and
the simulation is rarely checked against a native sparse flight of the same
stand. Third, research code has to be adapted to new data, and an adapter defect
can be mistaken for domain shift.

This paper addresses the question with a benchmark built to control those
obstacles. We ask (i) how much point density changes detection accuracy, and for
which detectors, (ii) which detectors recover understory trees, and (iii)
whether the ranking of detectors at native density predicts their ranking on
sparser clouds. Our contributions are:

1. An equal-support benchmark of three zero-shot 3D instance segmenters, six
   classical detectors and two RGB detectors at five sites in two regions, on
   sealed, seeded clips at six densities including the QL2 floor, pooled by
   counts with paired plot-level bootstrap intervals and stratified by field
   crown class.
2. Reference-completeness scoring: precision inside censused subplots, with the
   nominal plot as a lower bound and a co-detection credit as a second bracket.
3. The density response of each detector, the stability of the ranking across
   density, the decomposition by site and region, and the understory floor.
4. A check of decimation against earlier, natively sparse flights of the same
   sensor family over the same plots for every learned detector, and against
   surveys of another sensor.
5. A dense-domain control with the same checkpoints and adapters, extended by
   thinning the dense benchmark to the sparse densities, and an account of two
   integration defects that had looked like domain shift.
6. An evaluation sensitivity analysis covering the matching rule, the tolerance,
   stem-position uncertainty, the temporal gap between census and flight, and
   the provenance of every configuration.
7. An open harness: frozen clips, pinned checkpoints, hash receipts and an
   archive whose tables rebuild with one command in a clean container.

The short answer to the title question is that native-density accuracy predicts
accuracy down to the QL2 floor and not below it, and that the advantage of
dense-trained segmenters over a simple CHM baseline on this benchmark is about
0.05 F1.

## 2. Related work

### 2.1 Benchmarks

Open benchmarks with per-point tree labels are dense. The FOR-instance
collections range from about 500 to 9,500 points/m² [@puliti2023forinstance],
and FGI-EMIT, a multispectral helicopter ALS benchmark, exceeds 1,000 points/m²
[@ruoppa2026benchmarking]. FOR-instance v3, introduced with SegmentAnyTreeV2,
states a floor of 10 points/m² obtained by subsampling
[@wielgosz2026segmentanytreev2]. NeonTreeEvaluation is the one benchmark built
on sparse ALS; it annotates crowns in imagery and uses field stems for recall
only [@weinstein2021benchmark]. International comparisons of classical detectors
used field stems at 2 to 20 pulses/m² [@kaartinen2012international;
@eysn2015benchmark]. We found no benchmark that scores deep 3D segmenters
against field stems at national-mapping density.

### 2.2 Point density

Studies of point density follow the same split. Classical work varies density
between 1 and 25 pulses/m² [@jakubowski2013tradeoffs;
@kaartinen2012international; @sparks2022crosscomparison]. Deep-model studies
vary it between 10 and 10,000 points/m², with the sparsest levels subsampled
from dense acquisitions [@wielgosz2024segmentanytree; @xiang2025forestformer3d;
@li2026itsnet]; the FGI-EMIT authors compare models trained from scratch on
subsampled versions of one boreal site [@ruoppa2026benchmarking]. We found no
paper that evaluates a pretrained 3D segmenter on native ALS at 1 to 2
pulses/m², and none that validates decimation against a native sparse
acquisition of the same stand.

### 2.3 Understory trees

Recall by crown class is reported mainly for classical methods on dense ALS
[@hamraz2017forest; @cao2023benchmarking]. Canopy-surface detectors miss trees
below the canopy by construction, and point-cloud methods were proposed to
recover them [@li2012new; @ferraz2016lidar]. We found no report of understory
recall for a deep model below 50 points/m².

### 2.4 Evaluation conventions

The dense-cloud community matches predicted and reference instances one to one
at an intersection over union (IoU) of 0.5; stem benchmarks match detections to
stems by restricted nearest neighbours [@eysn2015benchmark]. Matching rules are
rarely compared, and we found no forestry study that contrasts greedy with
optimal assignment. Reference incompleteness is acknowledged but seldom
measured. Checkpoint provenance is self-reported: we found no audit of overlap
between a checkpoint's training data and a benchmark's test data.

### 2.5 Recent models

The current state of the art includes SegmentAnyTreeV2
[@wielgosz2026segmentanytreev2], SelectAnyTree [@nguyen2026selectanytree], ForPT
[@yue2026toward] and ITS-Net [@li2026itsnet]. None reports performance at 1 to 8
pulses/m², and none had public weights when our runs were frozen; the
SegmentAnyTreeV2 preprint announces release on acceptance. We therefore evaluate
the first SegmentAnyTree [@wielgosz2024segmentanytree], ForestFormer3D
[@xiang2025forestformer3d] and TreeisoNet [@xi2025new].

## 3. Data

### 3.1 Sites and airborne LiDAR

The benchmark uses five terrestrial sites of the National Ecological Observatory
Network (NEON) in two regions (Table 1, Fig. 1). The California sites lie on a
gradient of canopy closure in the Sierra Nevada: San Joaquin Experimental Range
(SJER), an open oak and foothill pine woodland; Soaproot Saddle (SOAP), a mixed
conifer forest; and Lower Teakettle (TEAK), a red fir and subalpine conifer
forest. The Washington sites are Wind River Experimental Forest (WREF), an
old-growth Douglas-fir and western hemlock forest, and Abby Road (ABBY), a
managed Douglas-fir forest.

All sites were flown by the NEON Airborne Observation Platform in 2021
[@neon2026discrete]: SJER on 31 March with a RIEGL Q780, and the other four
between 12 and 24 July with an Optech Galaxy Prime. The discrete-return clouds
have a median density of 17.9 points/m² and 9.8 first-return pulses/m² over the
benchmark plots, close to the QL1 specification. All 80 tiles used match the
2026 NEON release by size and checksum.

**Table 1.** Sites and reference population. Plots are tower / distributed.
Crown classes are overstory (dominant and codominant) / understory (intermediate
and suppressed) / not classed. Pulse density is the median and range of
first-return density over the plot clips at native density.

| Site | Forest | 2021 flight | Plots | Stems | Crown classes | Pulses/m² | Censused plots / references |
| --- | --- | --- | --- | ---: | --- | --- | --- |
| SJER | Open oak and foothill pine woodland, California | 31 March, RIEGL Q780 | 6 (6 / 0) | 57 | 27 / 1 / 29 | 9.6 (6.4–13.2) | 2 / 14 |
| SOAP | Mixed conifer, California | 12–13 July, Galaxy Prime | 18 (7 / 11) | 231 | 184 / 44 / 3 | 12.2 (7.8–16.0) | 1 / 2 |
| TEAK | Red fir and subalpine conifer, California | 13–14 July, Galaxy Prime | 19 (6 / 13) | 374 | 316 / 52 / 6 | 11.7 (7.7–17.8) | 9 / 119 |
| WREF | Old-growth Douglas-fir and western hemlock, Washington | 18–24 July, Galaxy Prime | 38 (20 / 18) | 1,063 | 638 / 404 / 21 | 8.8 (5.2–15.2) | 28 / 642 |
| ABBY | Managed Douglas-fir, Washington | 19 and 24 July, Galaxy Prime | 25 (13 / 12) | 800 | 707 / 91 / 2 | 10.2 (6.6–12.3) | 17 / 413 |
| All | | | 106 (52 / 54) | 2,525 | 1,872 / 592 / 61 | 9.8 (5.2–17.8) | 57 / 1,190 |

![Figure 1. Reference stems by crown class, native pulse density and stem heights at the five sites.](figures/figure_1.png)

**Figure 1.** The reference population. Left: stems by field crown class at each
site. Centre: first-return pulse density of the native plot clips; the dotted
line is the QL1 floor of 8 pulses/m². Right: field heights of the reference
stems.

### 3.2 Field reference

The reference is the NEON woody vegetation structure product
[@neon2026vegetation]. Each mapped stem is recorded as a distance and azimuth
from a surveyed point of its plot, which we convert to map coordinates with the
coordinates and uncertainties of the NEON location service. Each stem is paired
with its measurement nearest to 2021 within four years, which supplies its
status, height, diameter at breast height (DBH) and canopy position.

The population was declared before any detector was run on it. A reference stem
is live, mapped and at least 10 cm in DBH, and lies inside the plot core: the
full 40 m × 40 m of a tower plot or the central 20 m × 20 m of a distributed
plot, the areas NEON maps. A plot enters the benchmark if it holds at least six
such trees. This gives 106 plots and 2,525 stems (Table 1). Two sensitivity
populations are scored alongside: one without the DBH floor (116 plots, 2,854
stems) and one without the six-tree rule (149 plots, 2,628 stems).

Crown class follows NEON's canopy position: full sun is dominant, partially
shaded codominant, mostly shaded intermediate and full shade suppressed. We call
the first two overstory and the last two understory. Of the 592 understory
stems, 404 are at WREF, so understory results are mostly a statement about that
old-growth site.

NEON does not census whole plots every year. A tower plot is censused in 800 m²
of its 1,600 m², and many plots have no full census in the flight year. Section
4.3 describes how we handle this.

### 3.3 Frozen clips and the density ladder

Every detector reads the same bytes. For each plot we clip the core plus a 25 m
buffer from the tiles, normalise heights with a triangulated ground surface, and
store the raw clip, the normalised clip, a 1 m terrain model and a manifest.
Sparser acquisitions are simulated by decimating all returns to a target density
on a 5 m grid, with a seed derived from the site, plot and target, before
normalisation, so that the terrain model also sees the sparser cloud. Three
measures make a clip reproducible byte for byte: single-threaded normalisation,
a canonical point order before sampling, and fresh worker processes. The root is
sealed by the SHA-256 of every file, and a detector refuses a clip whose hash
does not match.

The ladder has all-return targets of 8, 4, 2 and 1 points/m². We report measured
first-return density, because pulse density is what acquisition specifications
state: the medians over the 106 plots are 9.8 pulses/m² at native density and
4.7, 2.5, 1.3 and 0.6 pulses/m² on the four rungs. The QL2 floor of 2 pulses/m²
falls between two of them. Before any detector was run on it, we declared one
more rung with a target of 3.2 points/m², chosen from measured densities alone
so that its median is 2.0 pulses/m², and froze it in a separate root with the
same population, native clips and seeds. At the three California sites, eleven
independent seeds of the decimation give a standard deviation of pooled F1 per
site of 0.005 to 0.028 for the baseline detector.

### 3.4 Native sparse flights and 3DEP clouds

To test decimation we use earlier NEON flights of the same plots that are
natively sparse: SJER in March 2017 and SOAP and TEAK in June 2018, with median
first-return densities of 3.9 to 5.0 pulses/m². References were rebuilt for
those years, and the comparison uses the 586 stems on 39 plots that are live in
both epochs. A second, cross-sensor check uses public USGS 3DEP clouds over the
43 California plots [@usgs2026usgs], extracted with PDAL [@butler2021pdal]. None
of the covering surveys is at QL2 density (their medians are 47, 31 and 5.7
pulses/m²), so that check compares two sensors decimated to the same target.

### 3.5 Dense-domain control

FGI-EMIT [@ruoppa2026benchmarking; @ruoppa2026fgiemit] provides manual per-point
tree labels for 1,561 trees in 19 plots of boreal forest in Espoo, Finland,
scanned from a helicopter at more than 1,000 pulses/m². We declared ten
development plots (841 trees) and a reserve of three plots (257 trees) before
running any model, selected the detector policy on the development plots, and
evaluated the reserve once.

## 4. Methods

### 4.1 Detectors

Table 2 lists the detectors. All settings were fixed before the benchmark
population was scored; Section 4.6 describes the provenance record.

**Table 2.** Detectors. The learned detectors are used zero-shot with their
published checkpoints.

| Detector | Type | Input | Training data | Implementation |
| --- | --- | --- | --- | --- |
| CHM-VWF | Local maxima on a canopy height model, height-dependent window [@popescu2004seeing] | Normalised cloud, first returns | None | lasR [@roussel2026lasr] |
| `multichm` | Local maxima over a stack of height-sliced canopy models, after @eysn2015benchmark | Normalised cloud | None | lidRplugins [@roussel2023lidrplugins] |
| `lmfauto` | Point local maxima, automatic window | Normalised cloud | None | lidRplugins |
| `ptrees` | Multi-scale point segmentation [@vega2014ptrees] | Normalised cloud | None | lidRplugins |
| AMS3D | Adaptive mean shift in 3D [@ferraz2016lidar] | Normalised cloud | None | crownsegmentr [@steinmeier2025crownsegmentr] |
| Li 2012 | Point-cloud region growing [@li2012new] | Normalised cloud | None | lidR [@roussel2020lidr] |
| ForestFormer3D | Transformer instance segmentation [@xiang2025forestformer3d] | Raw cloud, whole scene | FOR-instanceV2: unmanned, mobile and terrestrial laser scanning [@xiang2025forinstancev2] | Published code and weights |
| SegmentAnyTree | Sparse convolutional instance segmentation [@wielgosz2024segmentanytree] | Raw cloud | FOR-instance and mobile scans, with copies sparsified to 10–1,000 points/m² | Published code and weights |
| TreeisoNet | Tree localisation and offset networks [@xi2025new] | Normalised cloud, 0.8 × 0.8 × 2.0 m voxels | Unmanned laser scanning at about 1,160 points/m², as described for the TreeAIBox models | TreeAIBox [@nrcan2025treeaibox] |
| DeepForest | Crown boxes in RGB imagery [@weinstein2020deepforest] | 10 cm camera mosaic [@neon2026camera] | Crowns from 22 NEON sites, then hand annotations from six, including SJER and TEAK | `deepforest-tree` [@weecology2024deepforesttree] |
| Detectree2 | Crown polygons in RGB imagery [@ball2023accurate] | 10 cm camera mosaic | Tropical forests and an urban site | Published weights [@ball2025detectree2] |

**The baseline.** CHM-VWF derives its parameters from measured density. The
canopy model is a triangulation of first returns rasterised at 0.25 m when the
clip has at least 8 first returns per square metre and at 0.5 m otherwise. Pits
are filled with lasR's pit filling, which is a fill applied to the rasterised
surface and not the pit-free algorithm of @khosravipour2014generating, and below
8 pulses/m² the surface is smoothed with a 3 × 3 mean filter. Tree tops are
local maxima in a circular window of diameter 0.1 h + 3 m, clamped to 3 to 5 m,
above 2 m. Eighteen of the 106 plots fall below 8 pulses/m² at native density
and take the 0.5 m branch there.

**Other classical detectors** run with package defaults or the parameters of
their source publications. Li 2012 is run at native density only, because the
segmenter is not meaningful on the sparsest clouds.

**Learned point detectors** receive the same clips, with no fine-tuning. Each
predicted instance is reduced to one apex, its highest point, expressed as
height above the frozen terrain model, and instances whose apex is below 2 m are
dropped. ForestFormer3D is run on the whole scene. TreeisoNet's apex pass uses
voxels of 0.8 × 0.8 × 2.0 m. Both settings were corrected after the dense-domain
control exposed defects (Section 5.7).

**RGB detectors** predict crowns in the 2021 NEON camera mosaic. A crown becomes
a detection at its centroid, with the height of the native canopy model there.
They have no density ladder and appear at native density only. A twelfth arm, a
promptable refiner seeded by CHM-VWF tops [@guo2024sam2point], lost most of its
seeds in dense plots and is not analysed.

### 4.2 Scoring

Detections inside the plot core are matched to reference stems one to one,
greedily by increasing horizontal distance, within 4 m. A height gate keeps a
short stem from taking a tall neighbour's apex: the detection's height must lie
between half the stem's height and the stem's height plus 8 m. Stems without a
height are matched on position alone. The 4 m radius covers the stem-mapping
uncertainty and the displacement between stem base and crown apex.

Recall is the share of reference stems matched, precision the share of core
detections matched, and F1 their harmonic mean. Rates are pooled by summing
counts over plots, never by averaging plot rates, so that a small plot does not
dominate. Within each density an equal-support guard keeps only the plot cells
that every included detector scored; with complete arms it drops nothing.

### 4.3 Reference completeness

A detection in a part of a plot that was not censused, or of a tree that was
censused but not mapped, counts against precision although it may be correct. We
bracket this bias in two ways.

**Censused subplots.** For each plot we take the nearest census of all growth
forms within four years of the flight, joined by census event, and reconstruct
its sampled footprint from the surveyed corners of the subplots, eroded by the
positional uncertainty plus 0.6 m. A subplot that holds a census target without
a usable mapped position is removed, because a correct detection there would be
scored as an error. Precision is computed from detections inside the remaining
interior, and recall from its references with the 4 m tolerance around it.
Fifty-seven plots are admitted (33 tower, 24 distributed), with 1,190 censused
references (Table 1); of the others, 20 have no full census in the window, 18
are lost to unmapped targets and 11 fail consistency or geometric checks. A
stricter rule that also removes subplots with a target lacking a height is
reported as a sensitivity, as is the exact 2021 census on 16 tower plots.

**Co-detection credit.** A false positive that has no matched stem nearby is
credited as a probable tree when detectors from at least two other families
(canopy-model, point-cloud, learned, RGB) each leave an isolated false positive
within 2 m of it. Credited F1 is a second bracket, reported separately.

The headline tables use the nominal plot core on all 106 plots, with precision
read as a lower bound; the censused scores are reported beside them.

### 4.4 Uncertainty

Every pooled number and every difference between two detectors carries a 95%
percentile interval from a paired bootstrap: plots are resampled with
replacement within each site, 1,000 times, and one set of draws is shared by all
detectors, densities and metrics, so that differences are paired. The intervals
express plot sampling only. Decimation noise (Section 3.3), stem-position
uncertainty (Section 4.8) and run-to-run jitter of the canopy model are
separate, smaller sources.

### 4.5 Rank stability

For the eight detectors with a full ladder we compute the Spearman correlation
between their F1 at native density and their F1 at each rung. Each bootstrap
draw ranks the detectors again, which gives the correlation an interval.

### 4.6 Development and replication regions

The Washington sites were added after the detectors had been run on the
California sites, and they hold 74% of the reference stems. A provenance record
lists every tunable setting, the data it was chosen on and the commit that fixed
it. Every setting behind the headline tables was fixed before the Washington
sites were scored, from California data, FGI-EMIT, the literature or package
defaults; four later changes are defect fixes or affect throughput only. We
therefore report California as the development region and Washington as the
replication region. Two limits apply. The subplot-exclusion rule of the censused
scoring was narrowed after censused scores that included Washington existed,
which is why the stricter rule is reported beside it. Credited F1 and the fusion
experiments of the supplement select configurations per site in sample and are
not part of the replication.

### 4.7 Decimation checks

On the native sparse flights we run CHM-VWF, `multichm` and the three learned
detectors on clips frozen from the 2017 and 2018 tiles, and score both the
sparse flight and the decimated 2021 rungs that bracket its density against the
same 586 stems. Differences carry paired plot-bootstrap intervals (2,000 draws).
The comparison mixes a sensor change with three years of canopy change, so it
shows the direction and rough size of the bias, not a correction. On the 3DEP
clouds, CHM-VWF and `multichm` are run on the 3DEP cloud and the NEON cloud
decimated to the same target on the same plots.

### 4.8 Sensitivity analyses

All sensitivity analyses re-score persisted detections; no detector is run
again. (i) Matching: Hungarian assignment, a tolerance scaled by field crown
width, a soft three-dimensional cost, and radii of 2 to 5 m. (ii) Stem position:
200 draws in which each stem is moved by its recorded positional uncertainty
(median 0.4 to 0.5 m). (iii) Temporal gap: scoring only against stems measured
in 2021, on the 44 plots that have any (1,318 of their 1,557 stems). (iv)
Tuning: a calibration and validation split of the baseline's parameter grid over
ten seeds.

### 4.9 Dense-domain control and thinning

On the FGI-EMIT reserve we run CHM-VWF, SegmentAnyTree and ForestFormer3D with
the checkpoints and the whole-scene inference of the NEON runs. Apexes are
scored with a greedy one-to-one matcher (4 m horizontally, 5 m in height) and
masks at IoU 0.5 against the manual labels. To separate density from the other
differences between the two datasets, we thin the ten development plots to the
NEON densities under a protocol declared before any thinned cloud existed, with
the seeded procedure of Section 3.3. The measured densities are 11.3, 5.4, 2.9,
1.5 and 0.7 pulses/m². Apexes are scored against all 841 reference apexes, with
a paired whole-plot bootstrap.

### 4.10 Implementation and reproducibility

The classical detectors run in R with lidR [@roussel2020lidr], lasR and
lidRplugins; the learned detectors run in containers built from the published
code, with checkpoint hashes and image identifiers recorded per run. Every table
in this paper is rebuilt from persisted detections by one script, which was run
in a clean container against the archive: of 1,221 rebuilt files none differed
from the archived copies beyond declared tolerances for canopy-model noise.

## 5. Results

### 5.1 Accuracy at native density

At a median of 9.8 pulses/m², ForestFormer3D and SegmentAnyTree have the highest
F1, 0.498 and 0.495, against 0.450 for CHM-VWF (Table 3). Their leads over the
baseline, +0.048 and +0.044, have intervals that exclude zero, and the two are
indistinguishable from each other. `multichm`, Li 2012, TreeisoNet and
DeepForest are indistinguishable from CHM-VWF. The detectors differ far more in
how they reach their F1 than in F1 itself: recall ranges from 0.46 to 0.71 and
precision from 0.15 to 0.44 among the LiDAR detectors, with the point segmenters
AMS3D and `ptrees` at the high-recall, low-precision end. The censused columns
of Table 3 are discussed in Section 5.5.

**Table 3.** Accuracy at native density (median 9.8 pulses/m²), five sites, with
95% intervals. Nominal plot core: 106 plots and 2,525 stems. Censused subplots:
57 plots and 1,190 references. The RGB detectors are not in the censused scorer.

| Detector | Recall | Precision | F1 | F1 lead over CHM-VWF | Censused precision | Censused F1 |
| --- | --- | --- | --- | --- | --- | --- |
| ForestFormer3D | 0.621 | 0.416 | 0.498 [0.478, 0.520] | +0.048 [+0.028, +0.069] | 0.675 | 0.668 [0.640, 0.695] |
| SegmentAnyTree | 0.604 | 0.419 | 0.495 [0.466, 0.522] | +0.044 [+0.021, +0.067] | 0.718 | 0.677 [0.644, 0.708] |
| `multichm` | 0.541 | 0.394 | 0.456 [0.435, 0.477] | +0.005 [−0.018, +0.028] | 0.636 | 0.597 [0.570, 0.626] |
| Li 2012 | 0.561 | 0.384 | 0.456 [0.426, 0.483] | +0.006 [−0.009, +0.019] | 0.692 | 0.638 [0.599, 0.676] |
| DeepForest (RGB) | 0.545 | 0.390 | 0.454 [0.428, 0.478] | +0.004 [−0.014, +0.022] | — | — |
| CHM-VWF | 0.464 | 0.438 | 0.450 [0.423, 0.478] | — | 0.779 | 0.608 [0.566, 0.651] |
| TreeisoNet | 0.514 | 0.394 | 0.446 [0.420, 0.470] | −0.004 [−0.018, +0.009] | 0.720 | 0.622 [0.581, 0.663] |
| `lmfauto` | 0.555 | 0.296 | 0.386 [0.352, 0.421] | −0.064 [−0.095, −0.030] | 0.492 | 0.539 [0.494, 0.594] |
| Detectree2 (RGB) | 0.309 | 0.435 | 0.362 [0.334, 0.390] | −0.089 [−0.120, −0.060] | — | — |
| `ptrees` | 0.712 | 0.215 | 0.331 [0.296, 0.369] | −0.120 [−0.154, −0.085] | 0.372 | 0.496 [0.439, 0.554] |
| AMS3D | 0.713 | 0.145 | 0.240 [0.214, 0.267] | −0.210 [−0.240, −0.180] | 0.243 | 0.364 [0.322, 0.404] |

### 5.2 Density response and rank stability

Down the ladder the detectors part (Table 4, Fig. 2). SegmentAnyTree holds to
the QL2 floor: at 2.0 pulses/m² its F1 is 0.449, level with ForestFormer3D,
TreeisoNet and `multichm` (0.449 to 0.452) and +0.058 [+0.036, +0.081] over
CHM-VWF. Below the floor it collapses, to 0.376 at 1.3 pulses/m², where it is
level with CHM-VWF (−0.007 [−0.030, +0.016]) and behind `multichm` (−0.064
[−0.093, −0.039]), and to 0.128 at 0.6 pulses/m². The loss is one of recall,
which falls from 0.604 at native density to 0.467 at the floor, 0.308 at 1.3 and
0.074 at 0.6 pulses/m², while precision rises slightly.

**Table 4.** F1 by density for the eight detectors with a full ladder, five
sites, nominal plot core. Columns give the median first-return density in
pulses/m²; the 2.0 column is the rung declared at the QL2 floor.

| Detector | 9.8 | 4.7 | 2.5 | 2.0 | 1.3 | 0.6 | Lead over CHM-VWF at 0.6 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ForestFormer3D | 0.498 | 0.487 | 0.457 | 0.452 | 0.438 | 0.421 | +0.047 [+0.022, +0.069] |
| SegmentAnyTree | 0.495 | 0.487 | 0.469 | 0.449 | 0.376 | 0.128 | −0.246 [−0.268, −0.223] |
| TreeisoNet | 0.446 | 0.452 | 0.453 | 0.449 | 0.444 | 0.440 | +0.066 [+0.037, +0.093] |
| `multichm` | 0.456 | 0.451 | 0.441 | 0.449 | 0.440 | 0.434 | +0.060 [+0.036, +0.082] |
| CHM-VWF | 0.450 | 0.395 | 0.396 | 0.392 | 0.383 | 0.374 | — |
| AMS3D | 0.240 | 0.313 | 0.389 | 0.412 | 0.459 | 0.437 | +0.063 [+0.033, +0.093] |
| `ptrees` | 0.331 | 0.444 | 0.414 | 0.405 | 0.360 | 0.271 | −0.103 [−0.122, −0.083] |
| `lmfauto` | 0.386 | 0.340 | 0.284 | 0.273 | 0.262 | 0.269 | −0.105 [−0.148, −0.063] |

The other two learned detectors do not share that cliff. ForestFormer3D declines
slowly, by 0.08 F1 over the whole ladder, and TreeisoNet is flat (0.440 to
0.453); both lead CHM-VWF by about 0.05 to 0.07 at 0.6 pulses/m². The classical
detectors differ as much among themselves. `multichm` loses at most 0.022.
CHM-VWF loses 0.055 at the first rung, where most plots cross to the coarser,
smoothed canopy model and its recall falls from 0.464 to 0.327, and little after
that. AMS3D gains as the cloud thins, from 0.240 to 0.459 at 1.3 pulses/m²,
because it splits fewer crowns; `ptrees` loses three quarters of its recall
(0.712 to 0.191); `lmfauto` gains recall and loses more precision. Neither
family has a characteristic response.

![Figure 2. F1, recall and precision against first-return pulse density for the eight ladder detectors.](figures/figure_2.png)

**Figure 2.** F1, recall and precision against median first-return pulse
density, five sites, nominal plot core, with 95% plot-bootstrap intervals.
Dotted lines mark the QL1 (8 pulses/m²) and QL2 (2 pulses/m²) floors.

The ranking at native density carries over to the QL2 floor and not below it
(Fig. 3). The Spearman correlation with the native ranking is 0.83 [0.69, 0.93]
at 4.7 pulses/m², 0.76 [0.55, 0.88] at 2.5 and 0.71 [0.38, 0.81] at 2.0, then
−0.05 [−0.17, 0.26] at 1.3 and −0.19 [−0.36, 0.14] at 0.6 pulses/m². Inside
censused subplots the same break appears (0.52 [0.14, 0.71] at 2.0 and 0.02
[−0.19, 0.21] at 1.3 pulses/m²). With eight detectors the intervals are wide,
but on the nominal plot core the intervals on either side of the floor do not
overlap.

![Figure 3. Rank of each detector down the ladder and the rank correlation with native density.](figures/figure_3.png)

**Figure 3.** Left: rank by F1 of the eight ladder detectors at each density.
Right: Spearman correlation between the ranking at native density and the
ranking at each rung, with 95% plot-bootstrap intervals.

### 5.3 Sites and regions

Site sets the level of accuracy more than the choice among the leading detectors
does. Native F1 for ForestFormer3D runs from 0.33 at SJER to 0.54 at ABBY, and
for CHM-VWF from 0.31 to 0.56. SJER, the open woodland with six plots, is the
hardest site for every detector and has wide intervals (0.17 to 0.47 for
CHM-VWF); ABBY, the managed forest, is the easiest for most, and there CHM-VWF,
Li 2012, TreeisoNet and SegmentAnyTree are within 0.015 of each other.

Washington replicates the California result at the top of the table (Table 5).
ForestFormer3D and SegmentAnyTree lead CHM-VWF in both regions, by about 0.09 in
the development region and 0.03 in the replication region, with all four
intervals excluding zero. Every detector scores higher in Washington and the
baseline gains more than the two segmenters, so their leads shrink. Li 2012 and
TreeisoNet gain most and move from behind the baseline to level with it, and in
Washington Li 2012 is indistinguishable from the two segmenters. Inside censused
subplots the two leads are close in both regions (+0.061 against +0.059 for
ForestFormer3D, +0.085 against +0.066 for SegmentAnyTree), but the censused
California scope is twelve plots and its intervals are too wide to separate the
regions.

**Table 5.** Development (California: 43 plots, 662 stems) and replication
(Washington: 63 plots, 1,863 stems) regions at native density, nominal plot
core.

| Detector | F1, California | F1, Washington | Lead over CHM-VWF, California | Lead, Washington | Difference of leads |
| --- | --- | --- | --- | --- | --- |
| CHM-VWF | 0.374 [0.334, 0.416] | 0.480 [0.448, 0.513] | — | — | — |
| ForestFormer3D | 0.459 [0.421, 0.505] | 0.512 [0.488, 0.537] | +0.086 [+0.054, +0.120] | +0.032 [+0.005, +0.059] | +0.054 [+0.013, +0.098] |
| SegmentAnyTree | 0.461 [0.408, 0.511] | 0.510 [0.478, 0.539] | +0.087 [+0.041, +0.131] | +0.030 [+0.006, +0.050] | +0.057 [+0.008, +0.106] |
| `multichm` | 0.428 [0.388, 0.469] | 0.467 [0.443, 0.492] | +0.054 | −0.013 | +0.067 [+0.024, +0.108] |
| DeepForest (RGB) | 0.423 [0.377, 0.467] | 0.466 [0.436, 0.493] | +0.049 | −0.014 | +0.063 [+0.023, +0.102] |
| Li 2012 | 0.352 [0.312, 0.392] | 0.500 [0.468, 0.529] | −0.022 [−0.046, −0.001] | +0.020 [+0.004, +0.037] | −0.041 [−0.071, −0.014] |
| TreeisoNet | 0.361 [0.323, 0.401] | 0.484 [0.455, 0.511] | −0.013 | +0.004 | −0.017 [−0.043, +0.009] |

The density response also differs between regions. CHM-VWF is flat across
density in California (every change from native within 0.02, every interval
spanning zero) and loses 0.07 at 4.7 pulses/m² and 0.10 at 0.6 pulses/m² in
Washington. SegmentAnyTree falls at every site, ForestFormer3D falls slightly at
every site, TreeisoNet and `multichm` stay within 0.05, and AMS3D rises at every
site; CHM-VWF, `ptrees` and `lmfauto` change sign between sites. At the QL2 rung
SegmentAnyTree leads CHM-VWF in Washington (+0.067 [+0.041, +0.094]) and is
level with it in California (+0.034 [−0.009, +0.082]), where it is already
behind `multichm` (−0.041 [−0.079, −0.005]): pulse density alone does not set
where it falls behind.

### 5.4 Understory trees

At native density the detectors recall 0.55 to 0.79 of the 1,872 overstory stems
and 0.12 to 0.63 of the 592 understory stems (Fig. 4). AMS3D finds understory
stems best (0.63 [0.56, 0.70]), followed by `ptrees` (0.46) and ForestFormer3D
(0.45 [0.39, 0.52]); `multichm` recalls 0.34, SegmentAnyTree 0.29, TreeisoNet
0.19 and CHM-VWF 0.17 [0.12, 0.23]. The two point segmenters pay for it with the
lowest precision of all detectors (0.15 and 0.22), so ForestFormer3D offers the
best understory recall among detectors with a precision near 0.4. Understory
recall falls with density for every detector except `lmfauto`, whose gain is
over-detection, and `multichm`, which holds near 0.33; ForestFormer3D keeps 0.23
at 0.6 pulses/m² and SegmentAnyTree 0.03.

![Figure 4. Overstory and understory recall against pulse density.](figures/figure_4.png)

**Figure 4.** Recall of overstory (dominant and codominant) and understory
(intermediate and suppressed) stems against median first-return pulse density,
five sites, with 95% intervals.

### 5.5 Reference completeness

Restricting the score to censused subplots raises precision for every detector
and every density, by 0.08 to 0.34, while recall moves by at most 0.024 (Fig.
5). On the same 57 plots CHM-VWF's native precision rises from 0.48 to 0.78. The
exact 2021 census on 16 tower plots moves precision in the same direction (0.79
against 0.44 for CHM-VWF), and the stricter exclusion rule lowers native
precision by about 0.01. Detectors with dense apexes keep a low censused
precision (0.24 for AMS3D), so most of their commission is real.

Inside censused subplots SegmentAnyTree and ForestFormer3D lead CHM-VWF by
+0.068 [+0.036, +0.100] and +0.059 [+0.020, +0.099] at native density (Table 3).
ForestFormer3D's lead over Li 2012, a region-growing method published in 2012,
is +0.029 [−0.007, +0.068] and no longer distinguishable from zero. On the 57
plots the nine LiDAR detectors keep the same F1 order in both scorings. The
censused table rests mostly on the Washington sites, which hold 1,055 of its
1,190 references.

The co-detection credit raises F1 by 0.07 to 0.14 per detector at its default
rule and leaves the two segmenters in the lead. Both brackets point the same
way: nominal-plot precision understates every detector. Inside censused subplots
it understates the baseline most: CHM-VWF's precision rises by 0.29 to 0.34
across densities, against 0.08 to 0.32 for the other detectors.

![Figure 5. Precision at native density by reference: nominal plot core, censused subplots and co-detection credit.](figures/figure_5.png)

**Figure 5.** Precision at native density under three references. Circles:
nominal plot core, with 95% intervals. Triangles: censused subplots. Arrows:
from raw to credited precision at each detector's selected configuration.

### 5.6 Decimation against native sparse flights

On the 586 stems common to both epochs, the natively sparse flights give lower
recall than the decimated 2021 rungs that bracket their density, for every
detector (Fig. 6). For CHM-VWF, `multichm`, ForestFormer3D and TreeisoNet the
gap is 0.03 to 0.05, with most intervals excluding zero. ForestFormer3D's F1 on
the sparse flights is level with both rungs (−0.016 [−0.043, +0.008] and +0.003
[−0.027, +0.032]); TreeisoNet's is about 0.04 lower, and CHM-VWF's 0.04 lower.
SegmentAnyTree's gap is several times larger: its recall on the sparse flights
(0.42) is 0.19 [0.16, 0.23] below the rung at about 5.4 pulses/m² and 0.06
[0.01, 0.12] below the rung at about 2.9 pulses/m². Its results on decimated
clouds are therefore upper bounds, and the density at which it falls behind on a
native acquisition may be higher than Table 4 suggests.

The cross-sensor check agrees within its noise. With both sources decimated to
the same target, CHM-VWF differs by −0.014 [−0.047, +0.016] F1 between the 3DEP
and NEON clouds and `multichm` by −0.030 [−0.055, −0.006].

![Figure 6. Recall on natively sparse flights and on decimated 2021 clouds.](figures/figure_6.png)

**Figure 6.** Recall on the natively sparse 2017 and 2018 flights and on the
2021 clouds at two decimated rungs and at native density, for the 586 stems live
in both epochs on 39 California plots: all stems, overstory and understory.

### 5.7 Dense-domain control

On the FGI-EMIT reserve the same checkpoints and adapters work as published
models should (Table 6): ForestFormer3D and SegmentAnyTree reach apex F1 of 0.78
and 0.75 against 0.49 for CHM-VWF, and mask F1 of 0.65 and 0.58 against the
manual labels. The dataset authors report 0.73 and 0.65 for the same two
architectures trained on FGI-EMIT and scored on other plots
[@ruoppa2026benchmarking], which is context and not a like-for-like comparison.
The lead of the segmenters over the baseline is 0.26 to 0.29 on the reserve and
about 0.05 on NEON.

Thinning the development plots shows how much of that contrast is density. At
11.3 pulses/m², the density that corresponds to native NEON, ForestFormer3D's
lead falls from 0.30 to 0.08 [0.03, 0.13], against 0.05 [0.03, 0.07] on NEON: at
that density the two datasets agree within their intervals. Below it they part.
From 5.4 pulses/m² down ForestFormer3D leads by 0.17 to 0.21 on thinned FGI-EMIT
and by 0.05 to 0.09 on NEON. Part of that difference belongs to the baseline,
which loses 0.14 on FGI-EMIT where its rule switches to the coarser canopy model
and 0.06 on NEON. SegmentAnyTree's lead does not fall to the NEON level even at
11.3 pulses/m² (0.16 [0.09, 0.21] against 0.04). We therefore report the two
datasets as a contrast that density explains only in part; forest structure and
reference completeness differ as well.

SegmentAnyTree's collapse does replicate against true labels: on thinned
FGI-EMIT its lead holds to 2.9 pulses/m², vanishes at 1.5 (+0.03 [−0.04, +0.10])
and reverses at 0.7 (−0.23). The collapse is a property of the model at these
densities, not of NEON's references. ForestFormer3D loses most between the dense
cloud and 11 pulses/m² (0.22 apex F1) and little below that.

**Table 6.** Apex F1 on FGI-EMIT. Reserve: three plots, 257 trees, native
density. Development: ten plots, 841 trees, thinned to the NEON densities. Leads
are over CHM-VWF with 95% intervals; the NEON columns give the five-site lead at
the corresponding rung.

| Plots | Pulses/m² | CHM-VWF | ForestFormer3D | SegmentAnyTree | ForestFormer3D lead | On NEON | SegmentAnyTree lead | On NEON |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Reserve | native | 0.488 | 0.776 | 0.746 | +0.288 | — | +0.258 | — |
| Development | native | 0.513 | 0.811 | 0.729 | +0.298 [+0.181, +0.385] | — | +0.216 [+0.110, +0.288] | — |
| Development | 11.3 | 0.507 | 0.590 | 0.666 | +0.083 [+0.034, +0.126] | +0.048 | +0.159 [+0.092, +0.206] | +0.044 |
| Development | 5.4 | 0.366 | 0.569 | 0.605 | +0.203 [+0.174, +0.229] | +0.092 | +0.239 [+0.196, +0.276] | +0.091 |
| Development | 2.9 | 0.354 | 0.565 | 0.543 | +0.210 [+0.175, +0.243] | +0.062 | +0.189 [+0.156, +0.221] | +0.073 |
| Development | 1.5 | 0.361 | 0.544 | 0.393 | +0.184 [+0.143, +0.218] | +0.055 | +0.032 [−0.036, +0.096] | −0.007 |
| Development | 0.7 | 0.344 | 0.515 | 0.116 | +0.171 [+0.127, +0.214] | +0.047 | −0.228 [−0.308, −0.162] | −0.246 |

The control also served its purpose as a check on integration. Our first NEON
runs had ForestFormer3D at F1 0.23 to 0.33 on the California sites and
TreeisoNet at 0.08 and 0.12 at two of them, which read as a failure to transfer.
An audit on FGI-EMIT traced the first to an adapter that staged tiles in a way
that selected the upstream fallback route and stitched conflicting labels; with
whole-scene inference ForestFormer3D rises to 0.33 to 0.50 on the same plots.
The second was a voxel setting that differed between sites: at one setting
TreeisoNet scores 0.28 and 0.37 where it had scored 0.08 and 0.12. Neither
defect raised an error, and both would have been reported as domain shift
without a control on data where the models are known to work.

### 5.8 Sensitivity of the evaluation

**Matching.** No matcher changes the conclusions (Fig. 7). Hungarian assignment
raises every detector's native F1, by at most 0.03, and by at most 0.04 with a
crown-scaled tolerance; the soft three-dimensional cost moves detectors by −0.02
to +0.01. The two segmenters lead CHM-VWF by 0.03 to 0.06 under every matcher
and for radii of 3 to 5 m, and the ranking of all detectors keeps a Kendall τ of
at least 0.85 with the baseline ranking. The radius is the lever that matters: 2
m lowers F1 by 0.04 to 0.16 and 5 m raises it by 0.01 to 0.04, for every
detector in the same direction.

**Stem position.** Independent jitter of each stem by its recorded uncertainty
gives 90% bands at most 0.008 F1 wide, a quarter or less of the plot-sampling
intervals, and the two segmenters beat CHM-VWF in every one of 200 draws. A
shared offset of a whole plot is not tested and would act like a change of
radius.

**Temporal gap.** Scoring only against stems measured in the flight year raises
recall by 0.01 to 0.04 for most detectors and lowers precision for all, because
the stems measured in other years still stand and their detections now count as
errors; F1 on this cut is a lower bound. SegmentAnyTree keeps its lead over
CHM-VWF on the cut in both regions (0.468 against 0.430 overall). ForestFormer3D
does not: its lead holds in California (0.354 against 0.278 on 11 plots) and
reverses in Washington (0.447 against 0.465 on 33 plots), because it had matched
64% of the stems the cut removes, against 32% for CHM-VWF. Its lead in the
replication region is therefore not robust to the reference window.

**Tuning.** Tuning the baseline's resolution and window on calibration plots
yields held-out F1 within a few hundredths of the fixed configuration, and the
best cell of the grid beats the fixed configuration in sample by 0.006 to 0.016.

![Figure 7. Sensitivity of F1 to the match radius, the matcher and stem-position jitter.](figures/figure_7.png)

**Figure 7.** Sensitivity of the evaluation at native density. Left: F1 against
the match radius. Centre: change in F1 from the default greedy 4 m matcher under
four alternatives, with 95% intervals. Right: width of the 90% stem-jitter band
against the width of the 95% plot-bootstrap interval for each detector.

### 5.9 Compute cost

The classical detectors, TreeisoNet and Detectree2 take seconds per plot;
ForestFormer3D takes one to two minutes and SegmentAnyTree four to seven (Table
7). For the two slowest the plot size sets the time more than the number of
points does.

**Table 7.** Wall time and peak GPU memory per plot at native density on nine
plots (one tower and one distributed plot per site), on an Intel Core i9-14900K
and one NVIDIA RTX 5090. DeepForest predicts every image tile of a site once, so
its time is a per-site cost.

| Detector | Runs on | Median wall time (s) | Maximum (s) | Peak GPU memory (MiB) |
| --- | --- | ---: | ---: | ---: |
| CHM-VWF | CPU | 2.9 | 3.6 | — |
| `multichm` | CPU | 6.0 | 7.6 | — |
| `lmfauto` | CPU | 2.3 | 2.5 | — |
| `ptrees` | CPU | 3.2 | 3.5 | — |
| AMS3D | CPU | 5.0 | 53.3 | — |
| Li 2012 | CPU | 3.7 | 9.2 | — |
| TreeisoNet | GPU | 7.9 | 8.6 | 2,886 |
| ForestFormer3D | GPU | 97.9 | 103.7 | 1,944 |
| SegmentAnyTree | GPU | 411.1 | 445.4 | 888 |
| Detectree2 | CPU | 8.1 | 9.2 | — |
| DeepForest | GPU | 265.7 | 326.3 | 962 |

## 6. Discussion

### 6.1 What the benchmark says to users of national-mapping LiDAR

At QL1-like density, about 10 pulses/m², two published segmenters used without
any training improve on a canopy-model baseline by about 0.05 F1, at 30 to 140
times its compute cost. The improvement is real, replicated in a second region
and stable under every matcher, but it is small, and on censused references a
region-growing method from 2012 is not distinguishable from the better of them.
The larger practical gain from ForestFormer3D is in the understory, where it
recalls 0.45 of the stems against 0.17 for the baseline at a similar precision.

At QL2-like density, 2 to 2.5 pulses/m², four detectors are level near F1 0.45:
ForestFormer3D, SegmentAnyTree, TreeisoNet and `multichm`, each 0.05 to 0.07
above CHM-VWF. One of them, `multichm`, is a classical detector that runs in
seconds on a CPU. On decimated clouds SegmentAnyTree is still in that group at
the floor; on a native sparse flight at 4 to 5 pulses/m² its recall was already
0.19 below the decimated cloud of similar density, so we would not rely on it at
QL2.

Below the QL2 floor, which covers legacy surveys, the choice at native density
is no guide. One of the two best detectors at 10 pulses/m² is the worst at 0.6,
the worst at 10 pulses/m² is the best at 1.3, and the rank correlation is
indistinguishable from zero. A detector for such data has to be chosen from an
evaluation at that density.

### 6.2 What separates the segmenter that collapses from the two that do not

The benchmark establishes that the collapse belongs to SegmentAnyTree at these
densities, on two datasets and against two kinds of reference, and not to
learned detectors as a family. It does not establish why. SegmentAnyTree is the
only one of the three trained with sparsified copies, down to 10 points/m² of
all returns, and it holds to about a third of that density before failing, so
the collapse is not a simple failure to extrapolate below the training range.
ForestFormer3D and TreeisoNet were trained on dense data only and degrade
gracefully. We note two candidate explanations without having tested them: a
clustering stage that needs a minimum of points per instance, as the fixed
instance filter of our dense-domain protocol does (it removed most crowns below
3 pulses/m²), and the coarse 0.8 × 0.8 × 2.0 m voxels of TreeisoNet's
localisation pass, which aggregate sparse returns. Ablations by the model
authors would settle this.

### 6.3 Why the lead is small on NEON

At the density of the native NEON clouds, thinning brings ForestFormer3D's lead
on FGI-EMIT down to the NEON level, so for that model most of the contrast
between a lead of 0.3 and a lead of 0.05 is the step from more than a thousand
to about ten pulses per square metre. That step, not the steps below it, is
where the dense-trained model loses most. Below 10 pulses/m² the two datasets
disagree, and the disagreement has at least three sources that the design cannot
separate: the baseline responds differently to its own resolution switch in the
two forests, the references differ (complete manual labels against partial
censuses of stems of at least 10 cm DBH), and the forests differ. We therefore
do not claim a general law for the size of the lead; we report a contrast
between two datasets and the density at which they agree.

### 6.4 The understory floor

Recall of understory stems is limited by occlusion, not by tuning. The detectors
that reach 0.46 to 0.63 do so by splitting the point cloud aggressively and have
precision of 0.15 to 0.22; the single-surface canopy detector stays below 0.2,
and the multi-layer one reaches 0.34. ForestFormer3D is the exception that
reaches 0.45 without that cost, and its advantage shrinks with density. Since
two thirds of the understory reference is at one old-growth site, this floor
should be re-measured where understory stems are censused more widely.

### 6.5 Integration defects look like domain shift

Two of the three learned detectors were at first misjudged by a wide margin
because of an adapter and a configuration value, neither of which produced an
error. A zero-shot benchmark that reports a published model failing on new data
should show the same code path succeeding on data where the model is known to
work. We also found that a detector's native-density score can depend on
post-processing fitted to dense clouds: a filter requiring 40 points per
instance removed nearly all detections at 0.7 pulses/m².

### 6.6 Combining detectors

Fusion of the detectors, reported in the supplement, buys little: at native
density no fused mode beats the best single detector, and at sparser densities
agreement of two detectors gains 0.01 to 0.02 F1 with a threshold chosen in
sample. The detectors' errors are not independent enough for voting to pay.

### 6.7 Limitations

The reference is incomplete. Censused subplots and the co-detection credit
bracket the bias but do not remove it, the censused table rests mostly on two
sites, and its exclusion rule was refined after scores existed, which is why a
stricter rule is reported beside it. Stems are paired with measurements up to
four years from the flight; on the exact-year subset ForestFormer3D's lead
reverses in the replication region.

Below 4 pulses/m² the sparse clouds are decimated, and decimation is optimistic:
mildly for four detectors and strongly for SegmentAnyTree. No native acquisition
at QL2 density covers the plots.

The sites are oak woodland and conifer forest in two western regions; no
broadleaf forest is included. SJER has six plots, and half of its stems lack a
crown class.

The learned detectors are evaluated zero-shot, as a practitioner would use
published checkpoints. NEON provides stems and not instance labels, so
fine-tuning would need another reference; the benchmark says nothing about what
training at these densities could achieve. Newer models had no public weights
when the runs were frozen, and the harness accepts new detectors without new
infrastructure. DeepForest's training annotations include two of the five sites,
so it is not zero-shot there.

Mask quality on NEON is not assessed in the main text: the only available
reference is a proxy built from stems and crown widths, which on FGI-EMIT cost
about a third of mask F1 and compressed differences between models. The proxy
scores are in the supplement as a ranking.

## 7. Conclusions

On national-mapping ALS scored against field stems, dense-trained 3D segmenters
used zero-shot improve on a density-aware canopy-model baseline by about 0.05 F1
at 10 pulses/m², and their advantage and their ranking depend on density in ways
that the method family does not predict. One state-of-the-art segmenter
collapses below the QL2 floor while two others do not; a classical multi-layer
detector matches all three at the floor; and the ranking of detectors at native
density is unrelated to their ranking below 2 pulses/m². Three practices made
these statements possible and are, we suggest, necessary for benchmarks of this
kind: scoring precision only where the reference is complete, checking
decimation against a native sparse acquisition, and running a positive control
on data where the models are known to work. The clips, detections, scoring code
and tables are public and rebuild with one command, so new detectors can be
added to the same table.

## CRediT authorship contribution statement

To be completed with the author list.

## Declaration of competing interest

To be completed by the authors.

## Declaration of generative AI and AI-assisted technologies in the writing process

During the preparation of this work the authors used Claude (Anthropic) to
assist with software development, analysis scripts, checks of the results and
drafting of the manuscript text. The authors reviewed and edited the content and
take full responsibility for the content of the publication.

## Data and code availability

All field, airborne LiDAR and camera data of the benchmark are public data
products of the National Ecological Observatory Network, released under CC0 1.0:
vegetation structure [@neon2026vegetation], the discrete-return LiDAR point
cloud [@neon2026discrete] and the camera imagery mosaic [@neon2026camera], from
the 2021 flights over SJER, SOAP, TEAK, WREF and ABBY. The cross-sensor check
also uses public-domain USGS 3DEP point clouds [@usgs2026usgs]. The frozen
evaluation clips, field-stem references, plot populations, per-cell results and
persisted detections, checkpoint hashes and container image identifiers are
archived at Zenodo (DOI to be assigned at deposit), with a script that rebuilds
every table from the archive. The code is available at
<https://github.com/devakellc/lidar-tree-benchmark> under the MIT licence.
Third-party models are used under their own licences and are not redistributed;
the archive lists their sources, versions and SHA-256 hashes. FGI-EMIT is
available from its authors under CC BY-NC-SA 4.0 [@ruoppa2026fgiemit].

## Acknowledgements

The National Ecological Observatory Network is a program sponsored by the U.S.
National Science Foundation and operated under cooperative agreement by
Battelle. This material is based in part upon work supported by the National
Science Foundation through the NEON Program. We thank the authors of FGI-EMIT
and of the open-source detectors evaluated here for releasing their data, code
and weights.

## References

The reference list is generated from `docs/references.bib` by the citation keys
in the text.
