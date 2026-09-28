# FGI-EMIT prospective reserve inputs and execution contract

This stage opens only the original reserve plots 1003, 1010 and 1023, after the
[development policy freeze](fgiemit-frozen-policy.md). The selected FF3D arm,
CHM-VWF and SAT controls, support, filters, scoring and reporting rules remain
fixed. It validates inputs and seals an execution plan without running a
detector, calculating performance, fitting calibration or selecting thresholds.

## Parent and data boundaries

`prepare_fgiemit_reserve.py` first replays the complete frozen policy chain,
including installed checkpoint identities and the pinned lasR runtime. It
requires a fresh output root outside the sealed development data root. It
rejects ancestors of that root as well. Source hashes and scope are checked
before parsing point records. There is no arbitrary plot-selection option.

The original reserve contains 54, 155 and 48 references, respectively. All 257
remain eligible, including edge, dead and short trees in the original A-D
categories. Historical test plots and development outputs are unchanged. The
earlier receipts retain their original closed-reserve flags: those describe
their own stages, not permission to open the reserve in this stage.

## Input preparation and replay

Use the existing development validation/export helpers and unchanged R
normalizer. Exclude only semantic class 5. Preserve all other original rows,
returns, background, duplicate XYZ and instance identities. Model geometry
contains no reference labels, semantic annotations, intensity or color. Its
only extra field is the original zero-based `source_row`. Reference clouds are
separate. Plot-local metric coordinates receive no invented EPSG identifier.

Measure first-return and all-return density over the retained XY convex hull.
Derive the CHM settings with the sealed density rule. Do not use published plot
area or total point density as a substitute for measured first-return density.

Normalization uses one CPU thread, geometric CSF with all returns, and TIN
interpolation with its unchanged edge extrapolation. Allow 600 seconds per
plot and one attempt. Record the command, log, dependency versions and any
failure. Continue input validation on the remaining original reserve plots
with the same settings; a failed plot prevents sealing an execution contract.
Do not overwrite or automatically retry an attempt. An interrupted or changed
parent/code run can leave unsealed partial files, which cannot admit execution.

Record negative heights, ground support, edge extrapolation and differences
from published tree heights without adjusting normalization or removing trees.
These diagnostics do not independently establish height accuracy. Construct
the same three symmetric reference profiles as development: maximum AGL for
the primary endpoint, isolated-top AGL and historical raw Z for diagnostics.
Each apex retains its selected point's XY and original row identity.

After preparation, replay the parents and seal hashes of all outputs. The
`--verify` path rechecks the original source points against geometry/reference
exports, annotation isolation, normalization identity, measured support,
diagnostics, reference profiles and the reconstructed execution matrix. It
accepts failed receipts as evidence of failure, returns a failure exit status,
and rejects a contract attached to incomplete inputs. Symlinked artifacts are
not accepted. Generated data live under `inputs/`; the matrix and reference
apex table live under `contract/` in the new job root.

## Fixed execution contract

Only complete validation of all three plots can produce the nine-cell matrix.
Order is plot 1003, 1010, 1023, each with CHM-VWF, SAT, then FF3D. Every cell
binds its model input, normalized geometry and reference hashes, measured
densities, retained rows, frame, reference count and frozen method settings.
There are nine primary apex cells and six primary instance-mask cells. Height
diagnostics remain separate. No development fold lookup or probability
threshold is transferred to the reserve.

Execution must use one cell at a time, one attempt per cell and a 3,600-second
timeout. Stop at the first detector failure. No automatic retry, fallback
tiling, checkpoint replacement, tuning, ensemble or post-reserve selection is
allowed. Preserve missing, failed and completed-empty outcomes; require all
declared cells for primary count-pooled comparisons. Retain per-plot counts
and original A-D categories. Do not promote a three-plot bootstrap interval to
a primary uncertainty claim.

The contract binds the existing admitted execution core and pinned runtime.
The existing development runner has development-only path and scope guards;
this preparation script does not call or weaken them. A subsequent reserve
runner must replay this contract, enforce reserve scope, mount only each
annotation-free model input read-only, keep references outside model
containers, and write inference outputs to a fresh sibling directory. The
matrix therefore records `runner_validated=false`, `execution_enabled=false`
and `inference_run=false`. Structural input validation does not establish GPU
resource feasibility or detector performance on these larger clouds.

Unknown upstream training overlap remains unresolved. Any later result is a
conditional within-dataset evaluation of the development-selected policy;
it is not an independent unseen-data test of the upstream checkpoints.
