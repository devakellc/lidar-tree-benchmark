# Rebuild record

This record keeps the history of the benchmark's reproduction archive: each
staging, each rebuild of a staged archive and what the rebuilds found. The
[archive guide](reproduction-archive.md), which every staged archive carries as
its README, describes what an archive holds, how to rebuild it, the tolerances
of the comparison, the layout and what is left out.

## Archive of 5 October 2026

The archive was staged on 5 October 2026 from commit `da13583` (36,250
files, 5.5 GB). It was rebuilt in the clean container on CPU with 8 cores on
5 October (55 minutes; 1,207 of 1,221 files byte-identical, 2 equal within
1e-8, 2 within the length and overlap allowances, 7 figure images and 3
native QL2 cross-check rows intermediate, none differing) and again on
6 October with the report kept: 55 minutes, exit status 0, 1,204 files
byte-identical, 2 equal within 1e-8, 2 within the allowances (SJER: height
RMSE 1.2 mm, summed crown IoU 0.0026), 13 intermediate (the 7 figure images,
the native QL2 cross-check's per-plot and pooled rows, two re-detected
treetop caches and the treetop export they feed, all lasR tie-break or
millimetre height differences), and none differing, missing or extra. The
steps of that rebuild took about an hour on 8 cores. The 6 October
`reproduction_report.csv` and console log are kept beside the archive under
`work/zenodo/reproduction_2026-10-06/`; the rebuild of the archive staged for
deposit keeps its own (last section).

## Steps added after it

The archive of 5 October does not hold the outputs of the steps added to the
rebuild script later. By 18 November 2026 no archive staged for deposit had
been rebuilt with them (the two tests below rebuilt staged copies on the
development machine); the staging for deposit is to cover them:

- from October: the chance-agreement null with its seed and minimum-shift
  checks, the leave-out and chance-corrected rank correlations, the baseline
  smoothing sensitivity, the instance audit, the density-routed pipeline and
  the redrawn figures;
- from the revision of 17 November 2026: the density of the scored plot cores
  and the routing banded by it (the whole-clip banding kept as a sensitivity),
  the unsmoothed baseline at the QL2 rung (`paper_runs_nosmooth_ql2/`) and the
  chance null of both unsmoothed runs, the chance null inside censused
  subplots (over the declared and the unsmoothed baseline) and on plot
  subsets, the chance-correction simulation with the clustering of the
  reference stems, the native QL2 cross-check with
  noise-class and withheld points removed, the count of noise-class points in
  the frozen clips, the reference and fire audit, and the figures redrawn on
  core densities;
- from 18 November 2026: the split-crown diagnostic
  (`paper_runs/sensitivity/split_crowns/`), which re-reads the persisted
  native-density detections, and Figure 2 redrawn as the evaluation protocol
  alone.

## Differences from the October run

Three points differ from the October run. The two runs of the baseline without
its smoothing are re-scored from their archived detections and not re-detected,
because lasR's canopy-model maxima change by one tree top in a few cells from
run to run (measured in the [baseline smoothing
sensitivity](../results/baseline-smoothing-sensitivity-results.md) study). The
reference audit runs offline from the perimeter responses archived in
`paper_runs/reference_audit/fire_cache/`. And dated backups of re-run outputs
(names holding `.YYYY-MM-DD`) are left out of the archive.

## Test rebuilds of 17 November 2026

A test of 17 November 2026, which staged a copy of the work directory and
rebuilt it on the development machine (not in the clean container), rebuilt
1,470 files: 1,424 byte-identical, 25 equal within the declared tolerances, 15
intermediate, and 6 that differed. Those six were put right in the work
directory and the code before the next staging. The matcher sensitivity's lead
table had been written before the code added its rows of lead changes. The
QL2 rung's matcher grid and chance null are written in the order of the run's
detector list, which differed from the rebuild script's, so the routing
contracts, which record those files' checksums, differed too. These were
regenerated with the script's own commands; their values are unchanged. The
script for the chance-corrected rank correlations paired detectors by their
position in two files, so with the rebuild's order it paired two detectors
wrongly at the QL2 rung; it now pairs each detector with itself, and the
archived correlations, computed from files in matching order, are unchanged.
The sixth file was the simulation's settings record, which then held its run
time.

A second test, staged from the finished branch on the evening of 17 November
2026 after these repairs and after the simulation's split-crown detectors and
the reference-stem clustering were added, rebuilt 1,483 files: 1,462
byte-identical, 7 equal within the declared tolerances, 14 intermediate, and
none differing, missing or extra. The intermediate files are the figures'
PDFs, two cached CHM-VWF tree-top files, and the native QL2 cross-check's
detection results, whose counts move by a tree or two between runs. The
split-crown diagnostic was added to the rebuild script the next day; run
separately against that staged copy and against the work directory, with one
core and with eight, it wrote byte-identical outputs, but by 18 November 2026
no staged archive held them.

With the steps added on 17 November 2026, the test rebuild took about three
hours on 8 cores, about 50 minutes of them for the chance null inside censused
subplots and 50 for the chance-correction simulation.

## Archive staged for deposit

The staging of the archive for deposit (the commit in its `CODE_COMMIT`, its
file count and size) and its clean-container rebuild are recorded here once
run. The deposit carries the report of that rebuild beside the archive.
