# Frozen transfer audit protocol

Declared before new training-plot inference on 2026-09-15. This is a bounded
integration audit, not model selection on the external test set.

## Data and controls

Use training plots **1001 and 1019 only**. Plot 1001 is the existing technical
preflight: 133 trees with A/B/C/D counts 38/23/52/20. Plot 1019 is selected
solely from metadata and the published forest-type table: the lowest training
stem density (28.294 trees/ha), deciduous dominated, sparse, minimal understory,
and eight category-A trees. It contrasts with the dense, conifer-dominated,
understory-rich preflight, but eight trees cannot establish generalization.

Reuse the existing checkpoints and environments. Run the frozen adapters on
the second plot, reusing the first plot's archived outputs. SegmentAnyTree and
classical Treeiso are unchanged controls. Checksum the existing test outputs
before and after the audit; do not rescore or overwrite them.

## Predeclared comparisons

| Arm | Comparison | Fixed conditions |
|---|---|---|
| All | Archived/frozen adapter output and lossless label/frame fixtures | Same reference, background definition, IoU 0.5, 40-point/1.5 m filters |
| ForestFormer3D | Per-cylinder versus existing stitched labels | Same model output, common cylinder support; no merge-distance search |
| ForestFormer3D | Current forward path versus documented upstream test path, if static inspection confirms a route mismatch | Same weights/configuration; consume full-scene output, never truncate labels to fit |
| ForestFormer3D | Point/label/score correspondence before and after export | Require equal lengths and explicit ID/background conventions |
| TreeisoNet | Existing minimum-shifted cutoff versus physical normalized-height cutoff at 2 m | Same forward pass, confidence 0.22 and checkpoint-native voxels |
| TreeisoNet | Assigned-only nearest-neighbor export versus full aligned labels with explicit background | Same forward pass and reference; report geometric projection effects separately |
| TreeisoNet | Raw IDs versus explicitly unassigned out-of-volume points, if unsupported points receive a tree ID | Same checkpoint volume; no resolution or confidence tuning |

Capture intermediate outputs only for these comparisons. A demonstrated
integration defect gets a focused regression and a narrow fix. Absence of a
defect or lack of performance improvement is also a valid outcome. Do not add
new thresholds or ablations in response to scores without declaring a separate
future experiment.

For cylinder comparisons, score every method on the same reference-point
support for that cylinder and report reference truncation explicitly. Also
report the complete-plot stitched result. Do not pool overlapping cylinders
as if they were independent plots.

Report supplementary location matches using the maximum-Z point of each
reference/predicted instance, a fixed 4 m XY and 5 m Z gate, greedy one-to-one
matching. These are diagnostic cloud apexes, not field stems. Retain official
point-set metrics as primary and A-D as the original category system.

## Integrity and error analysis

Test ID/background round trips, point permutations, coordinate restoration,
vertically overlapping crowns, duplicate-coordinate ambiguity, negative
normalized heights, and incomplete prediction support. A nearby source point
alone is not evidence that its label corresponds to the correct input point.

Record predicted counts, assigned/reference support, unmatched predictions,
and overlap-based split/merge/background diagnostics with explicit definitions.
Inventory checkpoint hashes, expected features, normalization, and documented
training origins. Unverified source training overlap remains unknown.

## Follow-on validation split

Treat the already observed FGI-EMIT test run as a fixed historical baseline,
not a new untouched holdout for changes motivated by it. No test-label tuning
or test rescore is part of this audit.

For eastern NEON follow-on work, predeclare **HARV as development/pilot and
BART as held-out site validation**, subject to a score-blind data/CRS/epoch
availability preflight. Freeze eligible plot IDs, acquisition years, density
rungs, and reference coverage criteria before running detectors there. Select
weights/thresholds only within HARV development folds grouped by whole plot.
Do not evaluate BART until the selected pipeline is frozen. If BART lacks
suitable coverage, stop that validation claim and register a replacement
before inspecting candidate performance; do not select a site by its scores.

This site split can assess field-stem detection transfer, not crown-mask
quality. Crown/refinement promotion requires separate genuine instance/crown
annotations and a declared holdout. No new architecture, full sweep, fine-tuning,
or universal sparse/RGB routing claim is part of this audit.
