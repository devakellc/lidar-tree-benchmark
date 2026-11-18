# Native USGS 3DEP Cross-Check of the Density-Ladder Sweep — Results

*Cross-check of decimation against native USGS 3DEP clouds.
The density-ladder sweep ([density-ladder-sweep-results.md](density-ladder-sweep-results.md))
**thins** a dense NEON cloud to simulate sparse acquisitions
("decimation-as-simulation", a stated caveat). This note pulls the **native**
USGS 3DEP cloud over the same NEON plots through the public entwine EPT catalog,
runs the **same** CHM-VWF detection pipeline natively, and asks: does decimation
faithfully predict native-sparse behaviour? Tooling:
[`scripts/native_ql2_crosscheck.R`](../scripts/native_ql2_crosscheck.R) +
[`scripts/native_ql2_paired.R`](../scripts/native_ql2_paired.R) +
[`scripts/ept_discovery.R`](../scripts/ept_discovery.R) +
[`scripts/clip_noise_audit.R`](../scripts/clip_noise_audit.R). Last run:
2026-11-17, with noise-class and withheld points dropped when a cached cloud
is read.*

## Adopted population (paper numbers)

Checked on 5 October 2026 and corrected on 17 November 2026 against the
declared `adopted` population of the
[frozen-clip study](frozen-clips-results.md) on the three California sites,
the only ones with a public 3DEP cloud in this workflow: 43 plots and 662
stems, every adopted plot of SJER, SOAP and TEAK. The detectors ran again on
the cached 3DEP clouds after dropping their noise-class and withheld points
(see the
[correction](#correction-of-17-november-2026-noise-in-the-cached-3dep-clouds));
the NEON side is the paper runs' frozen 2 points/m² rung (1.3 first-return
pulses/m² median over five sites, about 1.5 on these California plots),
CHM-VWF at `a` = 0.10 and 0.5 m, and `multichm`.

```sh
export CLAUDE_JOB_DIR=$(pwd)/work/paper_runs
Rscript scripts/native_ql2_crosscheck.R SITES=SOAP,SJER,TEAK POP=adopted \
    CACHE_JOB=$(pwd)/work      # reuse the provenance-checked 3DEP clouds
Rscript scripts/native_ql2_paired.R   # paired plot bootstrap of the two sources
```

None of the covering 3DEP surveys is at QL2 density. Counted inside the
±45 m box around each plot, their median first-return density is 42 (SOAP),
29 (TEAK) and 5.4 (SJER) pulses/m², and 41, 28 and 5.5 inside the plot cores
([density](#native-3dep-density-counted-where-it-is-divided)). No native QL2
comparison is therefore possible here. The test is the cross-source one: the
3DEP cloud decimated to 2 points/m² against the NEON cloud decimated to the
same target, on the same plots and stems, with paired plot-bootstrap
intervals (1,000 resamples). The 3DEP decimation is seeded per plot
(`seed_for(site, plot, "3DEP-2")`) and both detectors read the same
realization. Decimated, the 3DEP clouds hold 1.3 first returns per m² in the
±45 m box and 1.2 in the plot cores (medians over the 43 plots).

| Detector | Source | Recall | Precision | F1 | 3DEP minus NEON, F1 [95%] |
| --- | --- | --- | --- | --- | --- |
| CHM-VWF | 3DEP decimated | 0.276 | 0.405 | 0.328 | −0.026 [−0.057, +0.006] |
| CHM-VWF | NEON decimated | 0.296 | 0.441 | 0.354 | |
| `multichm` | 3DEP decimated | 0.524 | 0.323 | 0.400 | −0.015 [−0.037, +0.009] |
| `multichm` | NEON decimated | 0.539 | 0.337 | 0.414 | |

**Readings.**

- For both detectors the two sources agree within the interval. Decimating
  another sensor's dense survey to the same target changes CHM-VWF's F1 by
  −0.026 (recall −0.020 [−0.049, +0.008], precision −0.036 [−0.075, +0.004])
  and `multichm`'s by −0.015 (recall −0.015 [−0.035, +0.008], precision
  −0.013 [−0.035, +0.012]).
- Before the correction, the `multichm` difference was −0.030
  [−0.055, −0.006] and excluded zero; most of its lower precision on the
  3DEP side came from the noise points. The CHM-VWF difference moved from
  −0.014 to −0.026.
- One decimation realization moves these differences by up to about 0.016:
  an earlier unseeded run on the unfiltered clouds gave +0.002 for CHM-VWF
  and −0.028 for `multichm`, against −0.014 and −0.030 seeded. Dropping
  points also changes the decimated realization, so part of each change is a
  new draw rather than the removed points themselves.
- Whether decimation predicts a true native QL2 flight is answered by the
  [native sparse epoch study](native-sparse-epoch-results.md), which uses
  NEON's own earlier, sparser flights; there, decimation is mildly optimistic.

## Correction of 17 November 2026: noise in the cached 3DEP clouds

**What was wrong.** This note said that the pull drops the noise classes 7
(low noise) and 18 (high noise) and every point flagged withheld. It drops
only the withheld points: PDAL's `filters.range` ORs ranges that name the
same dimension, so the two class clauses of its limits string
(`Classification![7:7],Classification![18:18],Withheld![1:1]`) together keep
every point. The class clauses, in the script from its first version, never
removed a point. The withheld clause was added on 5 June 2026, after 40 of
the 43 clouds used here had been pulled and cached that day; the other three
(SOAP_003, SOAP_017 and TEAK_014) were pulled with it on 5 October 2026 and
hold no noise-class or withheld points. The cache test keys only on the EPT
URL, the pad and the output CRS, so every later run, the paper numbers of
5 October 2026 included, reused the 40 June clouds unfiltered. An internal
review found the noise-class points. Its count of withheld points read the
clouds without the withheld flag and found none, but there are many: every
class 7 and 18 point is also flagged withheld, and a further 4.1% (SOAP) and
4.3% (TEAK) of the points are withheld points of class 1 (unclassified). Those
lie at the swath edges, all at scan angles beyond 25°, where about a quarter
of the points are withheld: the geometrically unreliable points that the USGS
lidar specification sets aside.

Points in the cached clouds of the 43 adopted plots:

| Site | Plots | Points | Class 7 | Class 18 | Withheld (all) | Dropped now |
| --- | --- | --- | --- | --- | --- | --- |
| SJER | 6 | 438,333 | 8 | 0 | 8 | 8 (0.002%) |
| SOAP | 18 | 12,679,480 | 21,226 | 49,742 | 596,688 | 596,688 (4.71%) |
| TEAK | 19 | 9,291,593 | 11,147 | 71,578 | 484,180 | 484,180 (5.21%) |

The noise classes alone are 0.56% of the SOAP points and 0.89% of the TEAK
points. The worst plots are TEAK_002, where 8.3% of the points are noise
classes (almost all class 18), and SOAP_004, where 15.3% of the points are
withheld. At TEAK_002 the review found 28,691 of the 42,738 noise points
inside the detectors' height window and 11,356 of them above the 99th
percentile of the plot's other heights, up to 80 m over a canopy whose 99th
percentile is 50 m: spurious tree tops.

**Effect on the comparison.** Paired over the same 43 plots and 662 stems:

| Detector | 3DEP clouds | 3DEP F1 | NEON F1 | 3DEP minus NEON, F1 [95%] |
| --- | --- | --- | --- | --- |
| CHM-VWF | as cached (5 October) | 0.340 | 0.354 | −0.014 [−0.047, +0.016] |
| CHM-VWF | classes 7 and 18 dropped | 0.337 | 0.354 | −0.017 [−0.047, +0.012] |
| CHM-VWF | classes 7 and 18 and withheld dropped | 0.328 | 0.354 | −0.026 [−0.057, +0.006] |
| `multichm` | as cached (5 October) | 0.384 | 0.414 | −0.030 [−0.055, −0.006] |
| `multichm` | classes 7 and 18 dropped | 0.395 | 0.414 | −0.020 [−0.043, +0.004] |
| `multichm` | classes 7 and 18 and withheld dropped | 0.400 | 0.414 | −0.015 [−0.037, +0.009] |

The last row of each detector is the corrected result. The middle rows drop
the noise classes only (`NOISE_FILTER=classes`) and reproduce the internal
review's re-run to the byte; that re-run assumed the clouds held no withheld
points. Per site, 3DEP minus NEON F1 of the pooled decimated rows:

| Site | Plots | Stems | CHM-VWF before | CHM-VWF after | `multichm` before | `multichm` after |
| --- | --- | --- | --- | --- | --- | --- |
| SJER | 6 | 57 | −0.049 | −0.049 | −0.001 | −0.001 |
| SOAP | 18 | 231 | −0.032 | −0.043 | −0.045 | −0.019 |
| TEAK | 19 | 374 | +0.007 | −0.007 | −0.030 | −0.017 |

SJER, with eight noise points, is unchanged. At full 3DEP density, which the
comparison does not use, the noise points had hurt `multichm` most: its SOAP
F1 rises from 0.227 to 0.392 (precision 0.155 to 0.294) and its TEAK F1 from
0.404 to 0.438, while CHM-VWF moves by at most 0.003 at any site. The
"high-density artifact" of `multichm` at SOAP in the historical section 5
below was therefore largely these noise points.

**What the script does now.** `ql2_noise_filter()` in
[`scripts/native_ql2_crosscheck.R`](../scripts/native_ql2_crosscheck.R)
drops classes 7 and 18 and withheld points every time a cloud is read,
whatever its age, before any density measurement or detection. Each per-plot
row of `ql2_detect_results.csv` records the filter (`noise_filter`) and the
points read, in class 7, in class 18, flagged withheld and dropped
(`n_read`, `n_class7`, `n_class18`, `n_withheld`, `n_dropped`).
`native_ql2_paired.R` stops on rows without that record or with different
filters at different sites. Fresh pulls record the filter in their sidecar
manifest. The cache test is unchanged, so the cached clouds are reused as
they are and nothing is pulled again. `NOISE_FILTER=0` reads the clouds as
cached and `NOISE_FILTER=classes` drops the noise classes only.

**Check that the filter is the only change.** With `NOISE_FILTER=0` the
corrected script reproduces the outputs of 5 October: the paired table to the
byte, and every decimated row and every `multichm` row of the per-plot
results. Of the 43 CHM-VWF rows at full density, two differ (one more match
at SOAP_015, one more detection at TEAK_011) and three more SOAP rows differ
in height RMSE by up to 6 cm. Three repeat runs of those plots on the same
input vary in the same way: lasR moves apex heights by centimetres between
runs on these dense 0.25 m CHMs, and the reproduction script compares these
rows loosely for that reason. Only the density columns change by design.

## Native 3DEP density, counted where it is divided

The densities reported before divided the points of the whole pulled cloud by
8,100 m², the area of the ±45 m box. The pulled cloud is larger: the query box
is the bounding box, in the EPT's Web Mercator SRS, of the UTM box, so the
cloud covers a square of about 92 m rotated by 1.2–1.6° (8,440 to 8,560 m²,
4–6% more than the box). With the noise and withheld points also counted,
the site medians were 6% (SJER), 8% (TEAK) and 12% (SOAP) high, and one plot
(SOAP_004) 25%. The script now counts the points inside the ±45 m box and
inside the plot core (±20 m tower, ±10 m distributed) and divides by that
box's area, after the noise filter. Detection still reads the whole cloud.
Site medians (minimum–maximum over plots), in points/m²:

| Site | Plots | Before: first returns, whole cloud / 8,100 m² | ±45 m box, first returns, as cached | ±45 m box, all returns | ±45 m box, first returns | Plot core, first returns |
| --- | --- | --- | --- | --- | --- | --- |
| SJER | 6 | 5.74 | 5.43 | 8.16 | 5.43 (2.38–8.07) | 5.45 (2.43–8.18) |
| SOAP | 18 | 47.31 | 45.18 | 78.05 | 42.18 (29.27–62.31) | 41.18 (29.09–67.67) |
| TEAK | 19 | 31.38 | 30.13 | 55.50 | 29.01 (18.08–48.56) | 28.40 (18.50–50.63) |

The never-upsample guard now compares the all-return density inside the box
(at least 4.28 points/m², SJER_046) with the 2 points/m² target, and the CHM
resolution follows the first-return density inside the box. No plot changed
status: all 43 plots ran for both detectors at full and decimated density
before and after, and no CHM resolution changed. The closest call is SJER_051
at 8.07 first returns per m², just above the 8 at which CHM-VWF switches from
0.25 to 0.5 m (8.50 as measured before). The decimated 3DEP clouds hold 2.08
points/m² in the box (site medians of 2.26 to 2.33 as measured before).

## Noise-class points in the NEON clips

The 3DEP side of this check drops classes 7 and 18 and withheld points; the
NEON side does not. The frozen NEON clips keep what the NEON tiles hold, and
every detector reads them as frozen.
[`scripts/clip_noise_audit.R`](../scripts/clip_noise_audit.R) counts those
points in every clip of the adopted population (106 plots at five sites, five
rungs each): in the raw clip that the learned detectors read, and in the
height-normalized clip that the CHM detectors read. It reads the sealed root
through its checksums and writes `neon/clip_noise_audit.csv` and
`neon/clip_noise_audit_summary.csv` under the job directory.

```sh
CLAUDE_JOB_DIR=$(pwd)/work/paper_runs Rscript scripts/clip_noise_audit.R
```

Native clips:

| Site | Plots | Points | Class 7 | Class 18 | Share | In the plot core | Left after normalization | Of those, ≥ 2 m |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ABBY | 25 | 3,000,356 | 147 | 0 | 0.0049% | 23 | 94 | 91 |
| SJER | 6 | 794,425 | 10 | 0 | 0.0013% | 2 | 2 | 2 |
| SOAP | 18 | 1,995,809 | 69 | 0 | 0.0035% | 4 | 19 | 19 |
| TEAK | 19 | 2,226,674 | 11 | 0 | 0.0005% | 0 | 11 | 11 |
| WREF | 38 | 4,285,437 | 1,364 | 0 | 0.032% | 38 | 1,061 | 95 |

- The NEON clips hold only low noise (class 7): between 0.0005% (TEAK) and
  0.03% (WREF) of the points per site. No clip holds class 18, and only the
  SJER clips hold withheld points (32 in the native clips).
- One plot carries most of it: WREF_009 has 1,013 class-7 points, 1.07% of
  its clip, four of them in the plot core. The 914 left after normalization
  all lie within 1 m below the ground surface, under the 2 m minimum
  tree-top height. Decimation keeps most of them, so their share of that
  clip grows to 3.8% at 1 point/m², and the WREF share to 0.086%.
- At the other sites the share stays below 0.01% at every rung. At the
  2 points/m² rung this check compares, the California clips hold 0 (SJER),
  12 (SOAP) and 2 (TEAK) noise points, five of them left after
  normalization.

At SOAP and TEAK the NEON noise is three to four orders of magnitude below
what the cached 3DEP clouds held; at SJER both are a handful of points. No
native NEON clip holds more than 20 noise points 2 m or more above ground.
The noise is recorded rather than removed, because the frozen clips are
sealed.

---

The sections below are the historical June 2026 check on the three-site
population (46 plots, 699 stems, six-stem gate). It ran on the same cached
clouds with their noise and withheld points, and its densities divide the
whole cloud by the ±45 m box area. Those sections are kept as recorded and
were not re-run.

---

## TL;DR (honest acquisition status first)

- **No public *native ~2-pulse QL2* cloud covers these NEON plots.** For each
  site the **preferred covering project** in the entwine public catalog
  (`raw.githubusercontent.com/hobuinc/usgs-lidar/.../resources.geojson`) is the
  one density-probed, and that preferred project is **far denser than QL2
  locally**: measured native first-return (pulse) density is
  **~44 / ~5.5 / ~31 pulses/m²** (median over plots), not ~2. (SOAP and TEAK have
  only the one covering project; SJER has two, and only the preferred QL2-tagged
  project was pulled — see §1.) The intended "pull a native ~2-pulse cloud"
  cannot be done from this preferred public data — reported truthfully rather
  than faked.
- **The QL designation in a project name is a floor, not the local density.**
  SJER is covered by `CA_FEMAR9Fresno_2_2019` — the `_2_` is the USGS **QL2**
  tag — yet its measured first-return density over the SJER plots is **2.5–8.5**
  (median 5.5), i.e. mostly above the 2 ppsm QL2 nominal.
- **Because no native sparse cloud is available, the equivalence test is a
  cross-source decimation check, made unit- and resolution-consistent.** Both
  arms thin to **all-return density `pdens = 2`** (the sweep's `homogenize`
  unit — *not* a pulse target), and both detect at **`chm_res = 0.5`**:
  - `native_dec2` — the *native non-NEON* survey decimated to `pdens = 2`.
  - `neon_dec2` — the cached *NEON* `rung==2, chm_res==0.5, vwf_a==0.10` arm.
  Same pipeline, same all-return target, same CHM grid, **different source
  sensor**. With both at `res = 0.5` the residual delta is genuinely
  sensor/return-structure, not CHM resolution.
- **`pdens = 2` all-return ⇒ `frdens ≈ 1.4–1.6` first-return.** Thinning *all*
  returns to 2 pts/m² leaves the *first-return* (pulse) density below 2 — so
  neither arm is "2 pulses/m² QL2". Measured first-return density per arm:

  | Site | native_dec2 frdens (med) | neon_dec2 frdens (med) |
  |------|:------------------------:|:----------------------:|
  | SOAP | 1.46 | 1.46 |
  | SJER | 1.69 | 1.60 |
  | TEAK | 1.34 | 1.43 |

  Both arms land at the same sub-2 pulse density, so the two-arm comparison is
  unit-consistent. We no longer call either arm "2 pulses/m² QL2".
- **Verdict — with CHM resolution matched, decimation is faithful overall and
  the residual error is a modest overstory bias.** Pooled overall recall agrees
  within **~0.07 at every site** (SOAP Δ = −0.027, SJER Δ = −0.070, TEAK
  Δ = −0.003). The largest remaining gaps are in the **dominant** class (SOAP
  −0.06, SJER −0.09, TEAK −0.12), where the native survey decimated to
  `pdens = 2` still under-detects the *NEON* cloud decimated to the same target.
  This is much smaller than the pre-fix figure: most of the previously reported
  −0.06…−0.09 overall and −0.21…−0.23 dominant gaps were a **CHM-resolution
  confound** (`native_dec2` had been detecting at `res = 1.0` while `neon_dec2`
  pooled at `res = 0.5`), not a sensor difference. The `*_dec2` arms carry
  ±1–2 TP of decimation randomness run-to-run, so these deltas wobble a few
  points between runs.
- **Native-full context:** at full native density these surveys detect at
  overall recall 0.49 (SOAP), 0.41 (SJER), 0.34 (TEAK) — consistent with the
  sweep's native rung and the SJER→SOAP→TEAK structure gradient.

---

## 1. EPT discovery (real, reproducible)

[`scripts/ept_discovery.R`](../scripts/ept_discovery.R) downloads the public 3DEP
entwine boundary index (`usgs.entwine.io/data/boundaries.json` is **404** as of
2026-06; the live mirror is
`raw.githubusercontent.com/hobuinc/usgs-lidar/master/boundaries/resources.geojson`,
~8.7 MB, WGS84). It buffers each NEON plot centroid by **1 km in the metric site
CRS (UTM 11N / EPSG:32611)**, unions the buffers, reprojects that hull to WGS84,
and intersects it against every project footprint — so a project covering the
plot margins (not only the exact centroid) still registers. Covering projects
found:

| Site | Covering public EPT project(s) | Resolved (preferred) EPT | EPT SRS |
|------|--------------------------------|--------------------------|---------|
| SOAP | `CA_SierraNevada_14_B22` | `.../CA_SierraNevada_14_B22/ept.json` | EPSG:3857 |
| SJER | `CA_FEMAR9Fresno_2_2019` (QL2), `CA_SierraNevada_11_B22` | `.../CA_FEMAR9Fresno_2_2019/ept.json` | EPSG:3857 |
| TEAK | `CA_SierraNevada_14_B22` | `.../CA_SierraNevada_14_B22/ept.json` | EPSG:3857 |

SOAP and TEAK are covered by **only one** public project — the 2022
`CA_SierraNevada_14_B22` high-density survey. There is **no QL2 project** over
them in the catalog. SJER has two: discovery prefers the QL2-tagged
`CA_FEMAR9Fresno_2_2019` (name score bonus for the `_2_` QL2 tag), the
genuine candidate.

All EPTs are **EPSG:3857** (Web Mercator). Distances there are inflated ~1.32×
at this latitude, so the pipeline reprojects to the metric `OUTCRS` (default
**UTM 11N / EPSG:32611**) before any metric step — the AOI box corners are
transformed UTM→3857 to form the `readers.ept` `bounds`, and
`filters.reprojection out_srs=OUTCRS` (mirroring
[`scripts/extract.json`](../scripts/extract.json)) brings the points back to the
metric CRS before detection. **Scoring is CRS-consistent:** detections come out
of the pipeline in `OUTCRS`, so the field stems (native NEON UTM 11N /
EPSG:32611) are reprojected into `OUTCRS` before matching. With the default
`OUTCRS = EPSG:32611` this stem reprojection is an identity transform; a
non-default `OUTCRS` no longer silently mismatches stems against detections.

### Provenance-gated LAZ cache

Each per-plot LAZ is pulled once and cached under `neon/<SITE>/ql2/<plot>.laz`
with a sidecar manifest `<plot>.laz.json` recording **`ept_url` + `pad` +
`outcrs`**. A pre-existing LAZ is a cache **HIT only when its manifest exists and
all three fields match** the current run; provenance is **never** inferred from
file size. A manifest-less LAZ — or one whose manifest records a different EPT,
AOI pad, or reprojection target — is a cache **MISS and is re-pulled**
(writing a fresh manifest). A pure detection-parameter change (e.g. this run's
CHM-resolution match) does **not** trigger a re-pull, because it does not change
`ept_url`/`pad`/`outcrs`. This run reused **all 43 cached LAZ as provenance
matches — no EPT re-pull occurred** (the manifests written by the prior run
already record the default `ept_url`/`pad = 45`/`outcrs = EPSG:32611`).

The manifest did not record the pull's filter. That filter never dropped the
noise classes (its two class clauses cancel), and this run's clouds were
pulled on 5 June 2026, before its withheld clause was added, so every run
reused them with their noise and withheld points. Since 17 November 2026 the
script drops those points whenever it reads a cloud, and new manifests record
the filter; see the
[correction](#correction-of-17-november-2026-noise-in-the-cached-3dep-clouds).

## 2. Acquisition status — native density actually obtained

For each eligible plot (≥6 mapped live-tree stems in the plot core; core ±20 m
tower / ±10 m distributed, mirroring `run_sweep.R`) a ±45 m AOI was pulled via
`pdal pipeline` and reprojected → laz. First-return density is measured
directly from the laz. This paragraph first said that the PDAL
`filters.range` drops the noise classes 7 (low noise) and 18 (high noise) and
any point with the Withheld flag set, and that the withheld set was
effectively empty for these surveys. Neither holds. PDAL ORs ranges that name
the same dimension, so the two class clauses keep every point and only the
withheld clause (`Withheld![1:1]`) removes any; that clause was added after
these clouds were pulled on 5 June 2026, so they hold both noise-class and
withheld points (4.7% of the SOAP points and 5.2% of the TEAK points of the
adopted plots). The densities below count them and divide the whole cloud by
the ±45 m box area; the
[correction](#correction-of-17-november-2026-noise-in-the-cached-3dep-clouds)
gives the measured values.

| Site | EPT project | Plots pulled | Native first-return ppsm (min / median / max) | ~2 ppsm? |
|------|-------------|:-----------:|:---------------------------------------------:|:--------:|
| SOAP | CA_SierraNevada_14_B22 | 16 | 32.9 / **43.9** / 67.5 | no (≈22×) |
| SJER | CA_FEMAR9Fresno_2_2019 | 8 | 2.5 / **5.5** / 8.5 | partial (3 plots ≈2.5) |
| TEAK | CA_SierraNevada_14_B22 | 19 | 21.4 / **31.4** / 43.9 | no (≈16×) |

The **only** plots that land near 2 ppsm are three SJER distributed plots —
`SJER_046` (2.5), `SJER_054` (2.7), `SJER_008` (2.8). Everything else is a
high-density survey. All three sites are therefore classified `dense` (median
native first-return density above the QL2 band). This is the honest reason the
"native QL2" comparison is reframed below as a **decimation cross-source check**
rather than a true native sparse run.

## 3. Native-vs-decimated comparison (pooled, by crown class)

Pooling matches the sweep exactly (`analyze_sweep.R`):

- **Recall** = `sum(TP) / sum(n_ref)`; per-class TP recovered as
  `round(rec_class × n_class)`.
- **Precision** = `sum(tp_core) / sum(n_det)`, where `tp_core =
  round(precision × n_det)` is recovered **per row**. The per-row precision
  numerator is core-only, but `TP` includes boundary matches outside the core;
  pooling `sum(TP)/sum(n_det)` would mix a boundary-inclusive numerator with a
  core-only denominator and **inflate precision**. This was fixed — corrected
  precision is reported below.

Three engines per site, **all detecting at `chm_res = 0.5`** for the two
decimated arms:

- `native_full` — detection at the survey's **native** density (context); its
  CHM resolution is derived from the native first-return density (`res = 0.25`
  for the dense surveys).
- `native_dec2` — the native non-NEON cloud decimated to **all-return
  `pdens = 2`**, CHM **pinned to `res = 0.5`** to match `neon_dec2`.
- `neon_dec2` — the **cached** NEON `rung==2, chm_res==0.5, vwf_a==0.10` arm
  from `sweep_results.csv`, same plots.

The equivalence test compares **`native_dec2` vs `neon_dec2`** (matched
all-return target, matched CHM grid, different source sensor).
`decimate_points(homogenize)` is random, so `*_dec2` recall jitters ±1–2 TP
run-to-run; `native_full` is deterministic.

### SOAP — mixed conifer (native median 44 ppsm; 16 plots, 222 stems)

| engine | overall | dominant | codominant | intermediate | suppressed | precision |
|--------|:------:|:--------:|:----------:|:------------:|:----------:|:---------:|
| native_full | **0.486** | 0.507 | 0.552 | 0.263 | 0.429 | 0.281 |
| native_dec2 (pdens→2, res=0.5) | **0.306** | 0.391 | 0.295 | 0.184 | 0.143 | 0.426 |
| neon_dec2 (pdens→2, res=0.5) | **0.333** | 0.449 | 0.324 | 0.158 | 0.000 | 0.466 |
| **Δ (native_dec2 − neon_dec2)** | **−0.027** | **−0.058** | −0.029 | +0.026 | +0.143 | −0.041 |

### SJER — open oak savanna (native median 5.5 ppsm; 8 plots, 71 stems)

| engine | overall | dominant | codominant | intermediate | suppressed | precision |
|--------|:------:|:--------:|:----------:|:------------:|:----------:|:---------:|
| native_full | **0.408** | 0.696 | 0.500 | 0.500 | — | 0.292 |
| native_dec2 (pdens→2, res=0.5) | **0.338** | 0.565 | 0.417 | 0.500 | — | 0.288 |
| neon_dec2 (pdens→2, res=0.5) | **0.408** | 0.652 | 0.500 | 0.500 | — | 0.337 |
| **Δ (native_dec2 − neon_dec2)** | **−0.070** | −0.087 | −0.083 | 0.000 | — | −0.050 |

### TEAK — red fir / high structure (native median 31 ppsm; 19 plots, 392 stems)

| engine | overall | dominant | codominant | intermediate | suppressed | precision |
|--------|:------:|:--------:|:----------:|:------------:|:----------:|:---------:|
| native_full | **0.342** | 0.679 | 0.271 | 0.107 | 0.500 | 0.336 |
| native_dec2 (pdens→2, res=0.5) | **0.222** | 0.429 | 0.171 | 0.089 | 0.000 | 0.411 |
| neon_dec2 (pdens→2, res=0.5) | **0.224** | 0.548 | 0.142 | 0.054 | 0.500 | 0.414 |
| **Δ (native_dec2 − neon_dec2)** | **−0.003** | **−0.119** | +0.029 | +0.036 | −0.500 | −0.003 |

### By height band (recall; short <8 m, mid 8–15 m, tall ≥15 m)

| Site | engine | tall | mid | short |
|------|--------|:----:|:---:|:-----:|
| SOAP | native_dec2 | 0.483 | 0.207 | 0.270 |
| SOAP | neon_dec2 | 0.534 | 0.241 | 0.257 |
| SJER | native_dec2 | 1.000 | 0.600 | 0.407 |
| SJER | neon_dec2 | 1.000 | 0.800 | 0.444 |
| TEAK | native_dec2 | 0.392 | 0.184 | 0.091 |
| TEAK | neon_dec2 | 0.456 | 0.136 | 0.084 |

## 4. Equivalence verdict

**Does decimation faithfully predict native-sparse behaviour?**

*Caveat up front:* this could not be tested against a true native ~2-pulse cloud,
because none is publicly available over these sites (§1–2). It was tested
against the strongest available proxy — a *different* native sensor decimated to
the same all-return `pdens = 2`, at the same CHM resolution.

- **Overall: faithful to ~0.07 recall at every site.** With the CHM grid
  matched, pooled overall recall agrees to **−0.027 (SOAP), −0.070 (SJER),
  −0.003 (TEAK)**. Decimation reproduces both the qualitative density response
  (overstory holds up, understory/short trees collapse) and the absolute pooled
  recall to within a few points. SJER carries the largest overall gap, but on
  only 71 stems across 8 plots, where ±1–2 TP of decimation randomness moves the
  pooled rate by several points run-to-run.
- **The residual error is a modest, structured overstory bias.** The remaining
  gaps concentrate in the **dominant** class: SOAP −0.06, SJER −0.09, TEAK −0.12.
  The likely cause is **sensor/return-structure differences** — all-return
  homogenisation equalises point count but not footprint, scan pattern, or
  multi-return distribution, so the resulting CHM apexes differ slightly for the
  tallest trees. The height-band view agrees: the tall band carries the SOAP/TEAK
  gap (−0.05 / −0.06), while mid/short are within ±0.20 (SJER mid −0.20 on just
  10 stems).
- **Most of the previously reported gap was a resolution confound, not the
  sensor.** Before this fix `native_dec2` selected `res = 1.0` from its decimated
  first-return density (`frdens < 4`) while `neon_dec2` was pooled at `res = 0.5`
  — the two arms ran at *different* CHM resolutions. Matching them collapses the
  overall delta from −0.06…−0.09 to ≤0.07 and the dominant-class delta from
  −0.21…−0.23 to ~−0.06…−0.12. The honest reading is that the coarser CHM, not
  the source sensor, drove most of the old under-detection.
- **Precision is also corrected.** Recovering core-only `tp_core` per row lowers
  the pooled precision relative to the previous (inflated) `sum(TP)/sum(n_det)`:
  e.g. TEAK `native_full` 0.40→0.34, SOAP `native_full` 0.31→0.28. The
  native_dec2 vs neon_dec2 precision gap is small at every site (≤0.05).

**Bottom line for the sweep's caveat:** with resolution and density units matched,
the density-ladder's decimation-as-simulation is a **faithful predictor of pooled
sparse-cloud recall (within ~0.07) and of the qualitative density response**, with
a **residual ~0.06–0.12 overstory (dominant) optimism** when a much denser cloud
is thinned rather than acquired sparse. Treat the sweep's absolute sparse-rung
recall as **slightly optimistic for the overstory**, but otherwise a reasonable
stand-in. A true public native ~2-pulse validation over these NEON sites is
**not currently possible** from the entwine catalog. The earlier, larger gaps in
this note were an artefact of an unmatched CHM resolution between the two arms,
now corrected.

## 5. multichm detector cross-check

The multichm out-of-sample question asks
the same question for the stronger classical arm, **multichm**
(`lidRplugins::multichm`, the density-ladder §8 / model-benchmark winner at
SOAP): does its advantage survive on **real** (3DEP-sourced) sparse data, not
just decimated NEON? The script now runs **both detectors on the same per-plot
native clip** and tests each against its **own** cached NEON dec2 baseline —
CHM-VWF vs `sweep_results.csv` (§3 above), multichm vs its
`multichm_sweep_results.csv` rung — so the native-vs-decimated equivalence is
judged **within detector, never across**. multichm uses its ladder-arm res rule
(0.25 m if first-returns ≥ 8 else 0.5 m); at the decimated `pdens = 2` arm the
first-return density is < 8, so it lands at 0.5 m — already matching its cached
dec2 rung, the same resolution-consistency the CHM-VWF arm gets by pinning 0.5 m.

The acquisition status (§1–2) is unchanged: **no native ~2-pulse QL2 cloud** is
available, so the equivalence is the same cross-source decimation check —
`native_dec2` (the native 3DEP survey thinned to all-return `pdens = 2`) vs
`neon_dec2` (the cached NEON dec2 rung), both at `res = 0.5`, different source
sensor. `*_dec2` carries ±1–2 TP of decimation randomness run-to-run.

### Is decimation faithful for multichm? (native_dec2 vs neon_dec2)

Pooled overall recall, multichm vs CHM-VWF, native_dec2 → neon_dec2:

| Site | multichm native_dec2 | multichm neon_dec2 | Δ (mc) | CHM-VWF Δ |
|------|:--------------------:|:------------------:|:------:|:---------:|
| SOAP | 0.608 | 0.622 | **−0.014** | −0.036 |
| SJER | 0.620 | 0.718 | **−0.099** | −0.028 |
| TEAK | 0.444 | 0.472 | **−0.028** | +0.015 |

Decimation predicts multichm's pooled sparse recall to within **~0.03 at the
conifer sites** (SOAP −0.014, TEAK −0.028) — as faithful as for CHM-VWF — and to
**−0.10 at SJER**, the largest gap for *both* detectors (71 stems over 8 plots,
where ±1–2 TP of decimation jitter moves the rate several points). Per crown
class the multichm gap concentrates, as for CHM-VWF, in the overstory at SJER
(dominant −0.17, codominant −0.25 on a handful of stems) and is small at SOAP
(dominant 0.00, codominant −0.06) and TEAK (dominant 0.00, codominant −0.02).

### Does multichm's advantage survive on the sparse 3DEP proxy?

On the **decimated-2** arm — the closest available sparse proxy — multichm keeps
the large recall advantage over CHM-VWF it showed on the NEON ladder, on *both*
the native-sourced and NEON-sourced clouds:

| Site | native_dec2 recall (mc / vwf) | neon_dec2 recall (mc / vwf) |
|------|:-----------------------------:|:---------------------------:|
| SOAP | **0.608 / 0.297** | 0.622 / 0.333 |
| SJER | **0.620 / 0.380** | 0.718 / 0.408 |
| TEAK | **0.444 / 0.240** | 0.472 / 0.224 |

multichm recovers **+0.31 (SOAP), +0.24 (SJER), +0.20 (TEAK)** more stems than
CHM-VWF on the native-sourced sparse cloud, at the §8 precision cost (SOAP
native_dec2 precision mc 0.33 vs vwf 0.39). So multichm's recall-first advantage
is **not an artifact of NEON decimation** — it reproduces on a *different sensor*
thinned to the same density. (SJER's higher multichm recall is again mostly
commission — precision mc 0.21 vs vwf 0.31 — the open-savanna pattern of §8.)

### Native-full context and a high-density caveat

At full native density (`native_full`, context only — these surveys are dense,
not QL2) multichm recall is **0.405 (SOAP, ~44 ppsm), 0.662 (SJER, ~5.5 ppsm),
0.446 (TEAK, ~31 ppsm)**. Note SOAP: at ~44 ppsm with `res = 0.25` multichm
**under-performs its own decimated-2 arm** (0.405 vs 0.608) and CHM-VWF native
(0.486), at very low precision (0.15) — a high-density / fine-resolution artifact
(the multi-layer CHM over-fragments and the 1:1 height-gated matcher loses true
apexes among spurious neighbours). It is not seen at SJER/TEAK and does not touch
the equivalence test, which uses the decimated-2 arm. It is a genuine note for
operators: multichm should be run at a density-appropriate resolution, not a fine
CHM on a very dense cloud.

*Revised 17 November 2026:* this reading does not survive the noise filter.
On the adopted plots, dropping the noise-class and withheld points raises
`multichm`'s full-density SOAP precision from 0.155 to 0.294 and its recall
from 0.424 to 0.584, close to its decimated arm (0.602); most of the SOAP
"artifact" was spurious tops on noise points (see the
[correction](#correction-of-17-november-2026-noise-in-the-cached-3dep-clouds)).

### Verdict (multichm cross-check, native-3DEP arm)

**multichm's SOAP/TEAK advantage survives on real (3DEP-sourced) sparse data, and
decimation predicts it faithfully.** With no true native ~2-pulse cloud
available, the test is the same cross-source decimation check as for CHM-VWF: on
the native 3DEP cloud thinned to `pdens = 2`, multichm beats CHM-VWF on recall by
**+0.31 / +0.24 / +0.20** (SOAP / SJER / TEAK), the recall-first edge of §8; and
its native_dec2 recall matches its NEON neon_dec2 rung to **−0.014 (SOAP),
−0.028 (TEAK)** — as faithful as CHM-VWF — with the familiar larger SJER wobble
(−0.10 on 71 stems). The one caveat is the dense `native_full` SOAP point above,
which is a fine-CHM-on-dense-cloud artifact, not a sparse-data result. Combined
with the cal/val arm
([calibration-validation-results.md](calibration-validation-results.md)),
multichm's conifer-site advantage holds **both out-of-sample and on real sparse
3DEP-sourced data**.

## 6. Reproduce

```sh
export CLAUDE_JOB_DIR=/path/to/work        # NEON ground truth + sweep_results live here

# 1. discover covering EPT projects (writes neon/<SITE>/ql2/ept_candidates.csv)
Rscript scripts/ept_discovery.R SITES=SOAP,SJER,TEAK

# 2. pull native AOIs via PDAL, run BOTH detectors (chm_vwf + multichm),
#    score, compare each to its own cached decimated-2 rung
Rscript scripts/native_ql2_crosscheck.R SITES=SOAP,SJER,TEAK
#   per-site:   neon/<SITE>/ql2/ql2_detect_results.csv  (detector column; +laz +json)
#   combined:   neon/native_ql2_vs_decimated.csv         (detector column)
# Override a site's EPT:  EPT_SJER=https://.../ept.json
# Tune the QL2 band classifier: QL2_LO=1.5 QL2_HI=4
# Read-time noise filter: NOISE_FILTER=1 (default: classes 7 and 18 and
#   withheld), NOISE_FILTER=classes (classes 7 and 18), NOISE_FILTER=0 (none)

# 3. noise-class points in the frozen NEON clips
Rscript scripts/clip_noise_audit.R
#   neon/clip_noise_audit.csv, neon/clip_noise_audit_summary.csv
```

All `*.laz` / `*.csv` outputs are gitignored — regenerate them. The cache is
provenance-gated (`<plot>.laz.json` records ept_url/pad/outcrs); a detection-only
re-run reuses the cached LAZ (no EPT re-pull), so adding the multichm arm did
**not** re-pull any LAZ. CHM-VWF §1–4 numbers are from the 2026-06-05 run; the
§5 multichm arm is from a 2026-06-10 re-run on the same cached LAZ. The
historical `native_full` rows were taken to reproduce exactly; on these dense
clouds a few CHM-VWF rows vary by one match between runs. `*_dec2` rows carry
±1–2 TP of decimation randomness.
