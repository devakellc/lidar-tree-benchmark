# Repository Guidance

## Scope and Sources

This file applies to work throughout this repository. Read [CLAUDE.md](CLAUDE.md)
before changing code; it remains the detailed companion for pipeline structure,
dependencies, and analysis-specific invariants. Keep shared guidance consistent
when changing either file.

This is a research and benchmark repository, not an application or R package.
Standalone R scripts and GPU model adapters evaluate tree-top detection and
crown delineation from airborne LiDAR. Deliverables include reproducible scripts,
Markdown reports, and generated benchmark artifacts.

- Use [README.md](README.md) as the canonical script and workflow index.
- Read the [methodology](docs/treetop-detection-approach.md) before changing
  detection parameters, and read the affected result report before editing its
  generating script.
- Inspect the current branch, worktree, code, and results before choosing work.
  Verify live tracking state when it determines dependencies or implementation
  order; do not treat old plans or remembered status as current evidence.

## Setup and Commands

Run commands from the repository root. Use `CLAUDE_JOB_DIR` for generated data;
the shared path helper defaults to the repository's `work/` directory.

```sh
export CLAUDE_JOB_DIR="$(pwd)/work"
mkdir -p "$CLAUDE_JOB_DIR"
Rscript scripts/detect_lasr.R
```

The example runs the bundled toy tile. R entry points generally take positional
`KEY=VALUE` arguments, such as `SITE=SOAP` or `RUNGS=native,8,4,2,1`. Check the
specific script's parser; do not assume every script accepts the same keys.
Reuse [scripts/repo_paths.R](scripts/repo_paths.R) and existing bootstrap helpers
to resolve code and working-data paths.

- Use the documented `r-lidar/lasR@pre-devel` build, not a CRAN replacement.
  Variable-window local maxima and parallel EPT acquisition depend on it.
- Core R dependencies include `lidR`, `terra`, `sf`, and `data.table`; NEON
  acquisition also uses `neonUtilities` and `jsonlite`. EPT extraction uses
  PDAL 2.9 or newer. Consult `CLAUDE.md` for the dependency constraints.
- For GPU work, read the relevant `gpu/*/README.md` and use its existing
  environment, checkpoint, and runtime settings. Do not silently install a new
  model version or replace a working environment.

## Methodology Invariants

- Measure density first, then derive CHM resolution, variable-window size, and
  smoothing. First-return density (`frdens`) controls those choices; all-return
  density (`pdens`) controls decimation and the no-upsampling guard.
- Preserve the engine split: lasR handles CHM and streaming workflows; lidR
  supplies point-cloud segmentation. lasR's TIN-based `pit_fill` is not
  `lidR::pitfree()` and must not be described as the same algorithm.
- Pool counts before calculating detection rates, not per-plot rates. Pool
  crown errors using their sums and sample counts, not per-plot RMSE values.
- Respect plot cores: tower plots use a 20 m half-width and distributed plots
  use 10 m through `plot_half()`. Do not score the unmapped surrounding ring.
- Keep one-to-one matching and the height-consistency gate. Changes to matching
  require explicit comparison with the existing default and regression tests.
- Tune only on the declared calibration or training subset. Preserve held-out
  splits, frozen inputs, and baseline artifacts; write changed experiments to
  distinct output locations and document their provenance.
- Compare detectors on equal site, plot, and density support. Report exclusions,
  failures, reference counts, and annotation limitations rather than silently
  dropping cells or substituting another model's output.
- Keep detection and crown-delineation metrics distinct. Compare equivalent
  crown diameter with `ninetyCrownDiameter` and max-caliper diameter with
  `maxCrownDiameter`; label Voronoi-on-stems instance metrics as proxies.
- Verify CRS, coordinate units, and height datum. Web Mercator (EPSG:3857)
  distorts metric distances; use the appropriate projected metric CRS for
  evaluation and distinguish absolute elevations from above-ground heights.
- In model adapters, preserve point identity, coordinate alignment, background
  labels, and instance IDs. Do not silently truncate arrays or project partial
  predictions onto unsupported points.

## Changes and Artifacts

- Preserve existing staged, unstaged, and untracked work. Keep edits scoped to
  the requested task; use an isolated worktree when unrelated changes would
  otherwise enter a commit or PR.
- Prefer existing R helpers, parsers, naming, and analysis patterns. Add focused
  regression tests for behavioral changes and broader coverage for shared
  scoring, pooling, cache, or export contracts.
- Generated clouds, rasters, CSVs, figures, caches, model resources, and local
  environments belong in the documented working locations. Do not force-add
  ignored artifacts or assume another checkout has local data or symlinks.
- Keep reports consistent with the code and actual outputs. Record the command,
  data scope, configuration, and limitations needed to reproduce each result.
  Distinguish planned work, completed runs, and unverified claims.
- Reports and user-facing documentation must stand alone. Use descriptive study
  names and document links, not issue numbers, PR numbers, or internal tracker
  IDs. Tracking references belong in GitHub discussions and commit messages.

## Verification and Publication

Before finalizing any issue or implementation, review [README.md](README.md)
against the completed changes and results. Update affected method summaries,
eligibility limits, workflow commands, requirements, script entries, and report
links. If no update is needed, say so in the completion summary. Keep historical,
training-only, and held-out results distinct; do not add tracking IDs to README.

For R code changes, run the repository test suite:

```sh
Rscript tests/run_tests.R
```

For Python or GPU changes, run the applicable tests in the documented model
environment. Use a bounded smoke test when the affected behavior needs real
data or hardware; unit tests alone do not establish benchmark performance.
State skipped tests, missing dependencies, and unavailable data explicitly.

Before creating or updating a PR, run these checks on the final worktree after
all code edits and report regeneration:

```sh
rumdl check --no-cache .
git diff --check
```

Fix all lint findings before publication; checking only changed documents is
not enough. Follow [.rumdl.toml](.rumdl.toml): 80-character prose lines, with
tables and fenced code blocks exempt. Keep any necessary rule exception narrow
and explained. Lint the final PR description with the same configuration.

Review the complete diff against the intended PR base, including staged changes
and newly added files. Include only the intended work and report the exact
verification performed. If a dependency is unmerged, confirm the stacked PR
base and explain its merge order in the PR description.
