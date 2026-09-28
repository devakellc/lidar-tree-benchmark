# FGI-EMIT Development and Evaluation Reserve

Declared on 2026-09-23 before any new detector execution or score inspection
on the remaining training plots. This declaration uses published metadata and
source headers only. It does not admit a real-data pipeline run.

## Population and Selection Rule

Use the pinned FGI-EMIT release from
[Zenodo](https://doi.org/10.5281/zenodo.19351234). Preserve the publisher's six
test plots as the already observed historical baseline. They are excluded from
development and from the new evaluation reserve.

Training plots 1001 and 1019 were used in the adapter audits and must remain
in development. For the other 11 training plots:

1. Sort by the published tree density in trees/ha, with plot ID as the tie
   breaker. This is stand density, not LiDAR return density or a model score.
2. Divide that order into three consecutive groups of sizes four, four and
   three. The remainder goes to earlier groups.
3. Reserve the lower median of each group for prospective evaluation: index
   two in each group, counting from one.
4. Put all remaining plots and the two prior audit plots in development.

The resulting reserve is **1003, 1010 and 1023**. Development is **1001, 1005,
1009, 1013, 1019, 1020, 1022, 1024, 1027 and 1031**. Do not choose a different
reserve after seeing scores, resource failures or inconvenient density ranges.
Unexpected evidence of previous processing on another training plot stops the
declaration instead of silently selecting a replacement.

This is a within-dataset split of the publisher's training release. It is not
the publisher's test split, independent site validation, or proof that these
plots were absent from upstream checkpoint training. Counts and categories in
published metadata are known; only new model predictions and evaluation are
reserved. Workspace inspection cannot establish that nobody has scored the
plots elsewhere.

## Development Folds and Comparison Scope

Declare ten leave-one-whole-plot-out development folds. Each development plot
is the validation plot of one fold; the other nine are its calibration pool.
All density variants and detector arms of a plot must stay in the same fold.
Neither prospective reserve plots nor historical test plots may enter any
calibration fit, threshold choice or model-selection step.

The initial comparison scope is **native density only**. Measured first-return
and all-return densities on the actual retained input support are prerequisites
for future inference. Header counts divided by rounded published areas are
inventory estimates, not approved density inputs. Native-density results will
not validate sparse-density routing or RGB fusion.

Candidate single-arm controls are SegmentAnyTree and classical CHM methods.
ForestFormer3D may be compared only through its indexed whole-scene path.
TreeisoNet remains deferred; classical Treeiso needs its annotation-assisted
exclusions disclosed before any inclusion. The comparison matrix, detector
configurations, score targets and calibration provenance must be separately
sealed before execution. This audit selects no final ensemble or thresholds.

The reserve may be evaluated once a development policy is frozen and all
admission checks below pass. Report failures on the declared population; do
not drop failed plots or replace them. Keep apex-distance detection and genuine
instance-mask metrics distinct, and pool counts/error sums on equal support.

## Admission Checks Still Required

- Declare the plot-local metric frame explicitly. Source files have no EPSG;
  assigning a geographic CRS merely to pass an interface check is invalid.
- Verify point identity, annotation/background conventions, boundary exclusions
  and scoring support against the original release before preparing inputs.
  Header/metadata inspection does not establish point-level annotation validity.
- Preserve real source return metadata when measuring density. The historical
  `fgi_model_points()` geometry bridge assigns placeholder return numbers; those
  prepared inputs cannot establish first-return density.
- Validate ground normalization and AGL conversion without copying the local
  minimum-Z convention into an above-ground-height claim.
- Audit checkpoint training overlap. Until then, keep upstream overlap unknown
  and avoid claiming an independent unseen-data test.
- Check resource limits on development inputs and freeze failure handling.
  Reserve plots include a cloud larger than the two whole-scene audit inputs.
- Seal per-arm provenance and metric-compatible calibration on development
  folds. Out-of-support density/site regimes must remain explicit, not use a
  fallback probability.

All real-data admission flags remain false in this audit. HARV/BART remains
retired. Existing data, predictions, metrics and the earlier audit declarations
are preserved.
