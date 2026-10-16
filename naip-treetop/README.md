# NAIP tree-top detection from 3DEP pseudo-labels (hand-off)

This repository holds the intermediate state of the experiment specified in
the doc "Tree-Top Detection on 30 cm NAIP": detect small trees on 30 cm NAIP
as tree tops with a stride-1 heatmap head, trained on tops derived from USGS
3DEP CHM local maxima, scored by height-binned point matching.

Work stopped at the request of the owner so it can continue on another
machine. **No experiment code has been written yet.** What exists:

| Path | What it is |
| --- | --- |
| [docs/plan.md](docs/plan.md) | The full implementation design for steps 1–5: modules, parameters, label rules, loss, evaluation, splits, caveats |
| [docs/findings.md](docs/findings.md) | What was verified so far: 3DEP EPT access, density correction, AOI scouting results, environment notes |
| [aois.json](aois.json) | Candidate CA/OR areas of interest with their scouted density and canopy structure |
| [scripts/scout_3dep_aois.R](scripts/scout_3dep_aois.R) | lasR script that reads a small square from a public 3DEP EPT and reports pulse density, acquisition date and the share of canopy returns per height band |
| [setup/install.sh](setup/install.sh) | Installs lasR from `r-lidar/lasR@pre-devel` and the Python packages the plan needs |

## Where to start

1. Run `setup/install.sh` on the target machine (it needs R ≥ 4.3, a C++17
   compiler, GDAL/GEOS/PROJ headers, and Python 3.10+; a CUDA GPU for steps
   2–5).
2. Re-run the scout to confirm EPT access and pick AOIs:
   `Rscript scripts/scout_3dep_aois.R` (about 40 s per AOI).
3. Implement step 1 (the label pipeline) following
   [docs/plan.md](docs/plan.md#step-1-label-pipeline-r-lasr--terra), and plot
   the height histogram of the extracted tops before any training.

The plan was written to fit into `agrigoriev/lidar_tree_benchmarks`
conventions (`CLAUDE_JOB_DIR`, `KEY=VALUE` arguments for R entry points,
`scripts/` for R, `gpu/` for model code, `unittest` tests), so it can be moved
into that repository later.

## Open question carried over from the spec

The doc assumed a 1.5–5 m target band for "small tree" and asked whether the
floor should sit lower. The plan keeps 1.5 m as the declared band edge, but
step 1 extracts maxima down to 1.0 m so the histogram can show where 3DEP
stops resolving tops before the floor is frozen.
