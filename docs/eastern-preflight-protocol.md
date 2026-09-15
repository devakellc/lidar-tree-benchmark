# Eastern-Site Preflight Protocol

This score-blind stage checks acquisition, reference coverage, coordinate
systems and density before any detector run or model selection. HARV is
reserved for development and BART for held-out site validation. No detection,
fusion, calibration fitting or BART performance inspection is authorized here.

## Selection Rules

- Archive public site and location metadata, product months and retrieval time.
  Record the release used for field measurements and authenticated file lists.
- Select the earliest common LiDAR/RGB acquisition year at or after 2021 for
  both sites, using availability only. Public metadata inspected on 2026-09-15
  gives August 2022; neither site lists 2021 AOP data. Do not substitute another
  year or site based on candidate detector performance.
- Match field observations to the actual acquisition year. For the initial
  smoke test, require an exact-year live-tree measurement, finite mapped
  coordinates and height, and a known tower/distributed plot type. Report
  missing observations and exclusions; do not treat them as absent trees.
- Require at least six eligible mapped trees inside the plot core. The core
  is 40 m square for tower plots and 20 m square for distributed plots.
  Require complete LiDAR tile coverage through the existing 25 m clip buffer.
- Choose the lexicographically first eligible HARV plot for the smoke test,
  before inspecting point-cloud density or detector scores. Enumerate and
  freeze all eligible plot IDs and the site split after data coverage checks.
  Public named locations alone do not establish eligible reference coverage.
- Record native all-return and first-return densities separately. Candidate
  rungs are native, 8, 4, 2 and 1 points/m2; admit numeric rungs only when below
  the measured native all-return density. Do not upsample or change the
  existing detector parameter rules.
- Verify actual acquisition dates and leaf-on status from acquisition metadata
  and imagery/phenology evidence. An August listing and peak-greenness flight
  policy are supportive context, not proof for the selected plot and flight.

## Coordinate and Cache Contracts

Derive the supported WGS84 UTM frame from field/location metadata and compare
it with LAS and RGB headers. Public location metadata identifies HARV as UTM
18N and BART as 19N. Reject missing, mixed, geographic, nonmetric or mismatched
frames before clipping or scoring. Transform coordinates explicitly when
needed; never relabel eastings/northings with a different EPSG code.

Record acquisition year and CRS in new reference/acquisition outputs. Frozen
clip reuse requires the same declared CRS, centre, core extent and buffer,
complete files and consistent spatial headers. Unversioned or incompatible
caches require a separate output root; never overwrite the old benchmark.
Use `CLAUDE_JOB_DIR=.../eastern_preflight` for this stage, keeping all original
California and external benchmark artifacts untouched.

## Access and Completion

NEON data downloads require an API token. Load `NEON_TOKEN` from the process
environment or a user-managed `~/.Renviron`, never a committed file or command
argument. Do not log tokens or embed them in URLs/manifests. Public site and
location metadata remain inspectable without a token.

An authentication, coverage, CRS or epoch failure is a recorded preflight
blocker, not permission to infer density, freeze unverified plots, substitute
data or run detectors. BART remains held out even when its availability and
coverage metadata are inspected. If it is unsuitable, declare a replacement
before any candidate performance is seen. Later pilot/calibration work needs
whole-plot-grouped HARV folds and a separately frozen comparison matrix.
