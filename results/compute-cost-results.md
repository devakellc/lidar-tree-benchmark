# Compute cost of the benchmark arms

Timed on 5 October 2026 with `scripts/compute_cost.sh`, after the paper runs,
on a quiet machine: an Intel Core i9-14900K (32 threads, 62 GiB RAM) and one
NVIDIA GeForce RTX 5090 (32 GiB, driver 595.84), one call at a time.

## Subset

The first tower and the first distributed plot of the `adopted` population at
each site, at native density from the sealed frozen clips. SJER's adopted
plots are all tower plots, so there are nine plots: SJER_046,
SOAP_031, SOAP_001, TEAK_043, TEAK_001, WREF_070, WREF_001, ABBY_061 and
ABBY_001. Their clips hold 45,465 to 173,650 points (median 128,339).

## Method

- **Classical arms.** Each arm's own detector function from its sweep script
  (`compute_cost_cell.R`), single-threaded, on the cell the paper runs read.
  Detection seconds are timed inside the process; wall time adds R start-up
  and reading the clip.
- **Learned and RGB arms.** Each arm's own sweep on a scratch job directory
  that holds only that plot, with the paper runs' settings. Wall time includes
  model load and container start, as in the paper runs.
- **Memory.** Wall time and peak resident memory come from `/usr/bin/time`,
  which sees the call and its child processes. ForestFormer3D, SegmentAnyTree
  and SAM2Point run in Docker, outside that process tree, so their host
  memory is not measured. A poller samples `nvidia-smi` every 0.5 s for the
  device memory in use above the idle level; it includes each framework's
  cache, not only its allocations.
- Every call exited 0.

## Results

Per plot, over the nine plots:

| Arm | Runs as | Median wall, s | Maximum wall, s | Total wall, s | Median detection, s | Peak host RSS, MiB | Peak GPU memory, MiB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| CHM-VWF | R, CPU | 2.9 | 3.6 | 25.5 | 0.80 | 302 | — |
| `multichm` | R, CPU | 6.0 | 7.6 | 52.8 | 3.97 | 441 | — |
| `lmfauto` | R, CPU | 2.3 | 2.5 | 20.9 | 0.21 | 268 | — |
| `ptrees` | R, CPU | 3.2 | 3.5 | 27.0 | 1.13 | 279 | — |
| AMS3D | R, CPU | 5.0 | 53.3 | 109.9 | 2.97 | 580 | — |
| Li 2012 | R, CPU | 3.7 | 9.2 | 38.2 | 1.62 | 282 | — |
| ForestFormer3D | Docker, GPU | 97.9 | 103.7 | 769.8 | — | not measured | 1,944 |
| TreeisoNet | Python, GPU | 7.9 | 8.6 | 66.8 | — | 1,285 | 2,886 |
| SegmentAnyTree | Docker, GPU | 411.1 | 445.4 | 3,210.1 | — | not measured | 888 |
| SAM2Point | Docker, GPU | 179.2 | 186.4 | 1,354.4 | — | not measured | 31,790 |
| DeepForest | Python, GPU | 265.7 | 326.3 | 2,195.5 | — | 3,376 | 962 |
| Detectree2 | Python, CPU | 8.1 | 9.2 | 65.6 | — | 1,229 | — |

## Readings

- **The classical arms are seconds per plot.** Detection itself takes 0.2 to
  4 s, except AMS3D on two plots (18 s at WREF_070 and 51 s at ABBY_001).
- **The learned point arms are minutes per plot, and the plot type sets it.**
  ForestFormer3D takes 64 to 69 s on the distributed plots (20 × 20 m cores) and
  98 to 104 s on the tower plots (40 × 40 m cores); SegmentAnyTree, the slowest
  arm, takes 251 to 297 s and 411 to 445 s. Within a plot type the time
  barely follows the point count. TreeisoNet takes 8 s.
- **SAM2Point's cost follows its prompts.** Each CHM-VWF prompt, up to 40, is
  a full SAM 2 video segmentation: 89 to 144 s on the distributed plots and
  179 to 186 s on the tower plots, which hold the most prompts. Its process
  takes nearly the whole 32 GiB card.
- **DeepForest's time is a per-site cost.** Its sweep predicts every RGB tile
  of the site once (154,335 boxes at SJER) and crops the plot from them, so
  one plot costs as much as a whole site: 113 s at SOAP to 326 s at ABBY.
  Detectree2 predicts only the plot's crop, on CPU.
- These are single runs on one machine, not a measure of run-to-run spread.
  The paper runs ran several plots in parallel for some arms, so their total
  times are not these totals.

## Reproduce

```sh
bash scripts/compute_cost.sh OUT=<new dir> WORK=work
```

Writes `compute_cost_cells.csv` (one row per arm and plot, with the exit
status), `compute_cost.csv` and `compute_cost.md`. Run it with the GPU idle
and the CPU quiet. The timings are not part of the reproduction archive's
rebuild: they depend on the machine.
