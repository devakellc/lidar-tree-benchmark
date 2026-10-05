# Configuration provenance

Checked on 5 October 2026. The Washington sites (WREF and ABBY) can serve as
a replication of the California sites (SJER, SOAP and TEAK) only if no
setting behind the paper runs was chosen after, or from, Washington scores.
This table records, for every tunable setting, its value in the paper runs,
the data it was chosen on and the commit that fixed it.

## When Washington was first scored

- WREF and ABBY were admitted on 2026-10-01 at 10:02 (`39f3a5f`) by a
  preflight that ran no detector and clipped no plot for scoring (see the
  [Pacific Northwest extension](../results/pacific-northwest-extension-results.md)).
- The frozen population was declared at 17:14 (`966a93c`); the root was
  sealed at 18:36:02.
- The first Washington scores were the CHM-VWF sweep files written at 18:38:42
  (WREF) and 18:39:11 (ABBY). No earlier Washington score exists in the
  working directory.

A setting committed after 2026-10-01 18:37 counts as "after" below. Times are
local (+04:00).

## Settings

| Arm | Setting | Value in the paper runs | Chosen on | Fixed | After? | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| TreeisoNet | Apex voxel | 0.8 × 0.8 × 2.0 m (run manifests) | TreeAIBox's ALS anisotropic setting, adopted after the June SOAP ladder | 2026-06-09, `34703d8` | No | The same value at every site |
| TreeisoNet | Confidence | 0.22 | Pooled F1 on five SOAP plots at the native voxel | 2026-06-08, `cf17f4c` | No | Not recalibrated after the voxel change; the plot IDs are not recorded |
| TreeisoNet | Mask voxel | Checkpoint voxel (0.1 m) | The June crown arm and the FGI-EMIT transfer audit | Value 2026-06-08 (`0718872`); argument split from the apex voxel 2026-10-01 21:32 (`8857d6b`) | Argument only | No TreeisoNet Washington run existed then. When later five-site results favoured the apex voxel for masks, the headline was not switched |
| TreeisoNet | Mask height cutoff, apex snap radius | 2 m, 2 m | The June crown arm; height frame corrected in the FGI-EMIT audit | 2026-06-08 (`0718872`), 2026-09-15 (`a19b52e`) | No | Batching on 2026-10-02 left results identical |
| ForestFormer3D | Scene layout | Whole scene (run manifests) | FGI-EMIT training plots 1001 and 1019, under a rule declared beforehand (prefer whole-scene regardless of scores) | Study 2026-09-15 (`17bc05b`); re-run declared 2026-09-30 (`87797f8`); NEON default 2026-10-01 19:12 (`2e63e48`) | Default only | An adapter defect fix to a pre-declared plan; the first ForestFormer3D Washington pass started at 21:11 |
| ForestFormer3D | Spacing, merge tolerance | 24 m, 2.0 m | The June SOAP cylinder route | 2026-06-09, `16aa463` | No | Inert for the whole-scene layout |
| CHM-VWF | Window slope `a`, window | `a` = 0.10; 0.1h + 3 clamped to 3–5 m; minimum height 2 m | Literature ([approach](treetop-detection-approach.md)); the June D17 grid moved F1 by at most 0.02 | 2026-06-05 (`2c3846a`), 2026-06-07 (`3d1cb11`) | No | |
| CHM-VWF | CHM resolution, smoothing | 0.25 m at ≥ 8 first returns/m², else 0.5 m with 3 × 3 mean smoothing | Literature rules of thumb; two-tier form from the D17 sweep | 2026-06-05 (`2c3846a`, `80e9071`), 2026-06-07 (`3d1cb11`) | No | The paper CSVs follow the rule exactly |
| `multichm` | Resolution, window, layers | Density-derived resolution; CHM-VWF window; layer 0.5 m, 2-D 3 m, 3-D 5 m | lidRplugins 0.4.0 defaults with the CHM-VWF allometry | 2026-06-07, `230731a` | No | |
| `lmfauto` | Height cutoff | 2 m | Package default | 2026-06-07, `230731a` | No | |
| `ptrees` | k, height cutoff | k = (30, 15), 2 m | lidRplugins example and default | 2026-06-07, `230731a` | No | |
| AMS3D | Crown ratios, height cutoff | 0.4, 0.8, 2 m | Literature default (Ferraz 2016 allometry), recorded in the arm's ledger | 2026-06-07, `1c12f82` | No | |
| Li 2012 | dt1, dt2, R, height cutoff | 1.5, 2, 2, 2 m | lidR 4.3.2 defaults | 2026-06-08, `d4930c9` | No | |
| Detectree2 | Plot crop | 35 m half-width (distributed) and 55 m (tower), mosaicked across RGB tiles | The runner's 40 m tiling grid | 2026-10-04 05:21, `ae6ce6d` | **Yes** | A defect fix: the old crop held no tile for distributed plots and truncated crops at tile edges. It was found on SJER and SOAP; the run stopped at TEAK before any Washington Detectree2 run, and the first Washington box was written at 05:25 |
| Detectree2 | Weights, crown cleaning, tiles | `250312_flexi.pth`; IoU 0.7, confidence 0.2; 40 m tiles with a 10 m buffer | Public weights and package defaults | 2026-06-21, `330a3cb` | No | |
| DeepForest | Model, patch, threshold | `weecology/deepforest-tree`; patch 400, overlap 0.05; package score threshold 0.1 | Package defaults | 2026-06-21, `fe4f693` | No | |
| SegmentAnyTree | All | Upstream defaults at `a3561ed` | Not tuned | 2026-06-09 (`43b538d`, `4c099d7`) | Workers only | Parallel workers (2026-10-02) gave identical results |
| SAM2Point | Prompts, voxel, seeds | 40 prompts; voxel 0.02 of the unit cube; CHM-VWF seeds | Compute cap; a two-plot SOAP proof of concept | 2026-06-21, `0d95188` | No | A later voxel pilot changed report text only |
| Scoring | Match tolerance, height gate | Greedy 1:1 within 4 m; apex height within [0.5h, h + 8 m] | D17; NEON stem-mapping uncertainty | 2026-06-05, `2c3846a` | No | A later fix (`0cbbcd5`) only affects references without heights |
| Population | Six-stem plot gate | ≥ 6 gated live stems | June D17 | 2026-06-05 (`2c3846a`); kept 2026-10-01 17:14 | No | Sealed before the first score |
| Population | Stem gate | DBH ≥ 10 cm | The WREF/ABBY preflight (sapling stands without a canopy position) | 2026-10-01 10:02, `39f3a5f` | No | Chosen from Washington reference data, not detector scores, and applied to every site |

## Verdict

The replication claim holds for the detector settings behind the master
tables. Every tunable value was fixed before Washington was scored, from
California data, FGI-EMIT, the literature or package defaults. Four changes
came later:

- the ForestFormer3D whole-scene default, a defect fix to a pre-declared plan,
  made before any ForestFormer3D Washington output;
- the TreeisoNet mask-voxel argument, which kept the existing value;
- the Detectree2 crop, a geometric defect fix made before any Washington
  Detectree2 run;
- SegmentAnyTree's worker count, which does not change results.

None of them is tuning, and none could have used that arm's Washington
scores.

## Limits of the claim

- **Censused precision.** The subplot-exclusion rule was narrowed on
  2026-10-01 at 22:39 (`2c8fb35`), two minutes after censused scores that
  included Washington were committed under the broader rule (`815f363`). The
  broader rule is kept as the declared strict sensitivity. The change mostly
  affects SJER (10 against 42 missing targets; WREF 17 against 22, ABBY 10
  against 11). The repository does not show whether the scores prompted it, so
  censused precision is reported with its strict sensitivity alongside.
- **Credited F1 and fusion** select each site's best configuration on that
  site's own pooled F1, a rule fixed in June (`992a014`), and fusion chooses
  its vote threshold in-sample. Their Washington numbers are therefore not
  out-of-sample, although the rule predates Washington. The development
  against replication comparison uses the master tables' fixed
  configurations only.
