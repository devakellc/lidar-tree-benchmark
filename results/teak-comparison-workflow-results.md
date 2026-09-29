# Historical TEAK comparison handoff

The [comparison workflow](../docs/teak-comparison-workflow-protocol.md)
connects the accepted historical TEAK inputs to a human review packet,
explicit admission checks and a guarded box-comparison entry point.
TEAK_043 remains model-observed development data. Current real inputs are
blocked; no accuracy score, detector ranking or new evaluation split is
produced. The eleven reserved candidates remain unprocessed and unadmitted.

The [native ensemble pipeline](final-ensemble-pipeline-results.md) remains
available for its completed conditional FGI-EMIT study. This handoff addresses
the additional evidence needed for TEAK-like deployment validation. It does
not change that pipeline's frozen FF3D default or promote a fusion variant.

## Review packet

The packet uses the native 400 by 400 pixel RGB core and all 24 unchanged
published boxes. It includes an unmarked image, a numbered-box view, original
geometry and provenance, and a 16-tile log covering the complete image,
including unboxed space. The original native RGB values remain opaque,
including channel value 255; the published raster's nodata interpretation
does not hide those samples. Model predictions are absent from the packet.

Separate templates record original-box keep/edit/remove decisions, new-box
additions, whole-image completeness and ambiguity, edge and split/merge
decisions, reviewer provenance, registration correspondences, timing evidence,
checkpoint exposure and crown-adapter evidence. Generated decision fields
remain blank or pending. Human review must create a new revision while
preserving the original packet and source annotations.

The software can check hashes, geometry, lineage and completed fields. It
cannot authenticate whether a person inspected the image or whether an
attestation is truthful. Whole-image observations and a human-supplied
attestation remain substantive requirements. The project's prior detector
observation is disclosed; a later review cannot turn this plot into an
independent holdout.

## Current admission boundary

The preflight reports every gate with its state, source identity and required
next evidence. Verified parent and native-input identities do not clear the
remaining scientific conditions.

| Condition | Current evidence | Required completion |
| --- | --- | --- |
| Parent and native-input integrity | Pinned historical packages, native point identity and measured density | Retain unchanged inputs and receipts |
| Reference revision and complete-image coverage | 24 published boxes; human decisions pending | Human adjudication, additions/removals and observations covering all image tiles |
| Spatial registration | No independent local ground correspondence assessment | Stable ground features, measurement uncertainty and a predeclared acceptance criterion |
| Acquisition timing | Conditional LiDAR date and camera candidates on two days; pixel contribution unknown | Source-backed timing evidence or a separately reviewed, explicitly bounded development claim |
| Checkpoint exposure | Training, pretraining, tuning and selection exposure remain unknown | Phase-specific evidence or an explicit conditional-development limitation |
| Crown-box compatibility | CHM treetops and neural sparse point-extent proxies only | Independently reviewed visible-canopy crown adapters with frozen construction and provenance |
| Paired comparison | No admitted crown-box arm set | Complete outcomes on identical image, native input and reference revision |

The [timing audit](teak-acquisition-timing-results.md) and
[mosaic compatibility audit](teak-mosaic-compatibility-results.md) retain their
unresolved findings. RGB similarity, frame footprints and camera-coloured
LiDAR points do not supply independent registration or selected-pixel
provenance. No additional pixel-matching search is performed here.

## Implemented comparison contract

A future real comparison requires a separately frozen, hash-bound evidence
bundle and a historical-development declaration. It cannot be admitted by
editing an earlier readiness flag. Reserved plots, independent-validation
claims, unresolved reference decisions and unsupported crown products are
rejected. This driver supports conditional historical box agreement only:
RGB exposure, exact lag and temporal agreement remain unknown. Timing and
checkpoint limitations need reviewed supporting evidence and an explicit
declaration. A result under this route cannot establish accuracy against
concurrent canopy observations or independent generalization.

Adapter checks bind source-instance identity, point membership, complete
disposition records, crown-boundary vertices and recomputed box geometry.
They reject unchanged sparse point extents and require reviewed crown
geometry evidence. Those checks cannot determine whether a polygon faithfully
represents visible canopy; changing a proxy's coordinates is not scientific
validation. The human method review remains necessary.

The comparator reuses the existing full-image clipping, IoU and stable
one-to-one maximum-cardinality assignment policy. Primary IoU 0.5 and
sensitivity IoU 0.4 remain separate, inclusive thresholds. Invalid boxes
are rejected before clipping; every positive-area intersection is retained
and outside predictions are counted separately. Counts are pooled before
rates, with undefined rates left unknown.

Every included arm must have the same admitted support and reference
revision. An explicit completed-empty outcome differs from missing, failed
or unrun predictions. Missing cells block the paired comparison. No synthetic
fixture result is presented as real TEAK performance, and no detector is
executed by this workflow.

## Historical detector replay

Integration review reproduced a verification defect: the original smoke
seals every Python and R script in its checkout, so unrelated later script
additions make direct verification from a newer checkout fail. Its commands
also bind the original absolute code location.

The [dedicated replay dispatcher](../scripts/replay_teak_detector_smoke.py)
authenticates the accepted receipt, preparation and attempt before deriving
the historical code path. It checks the original code inventory and invokes
the unchanged verifier from the retained checkout. It exposes no inference
or retry mode and checks that accepted artifacts remain unchanged. The
original scripts and receipts are preserved.

This is local replay requiring retained historical code, absolute paths,
parent packages and installed resources. It is not a portable archive. See
the [replay instructions](../docs/teak-detector-smoke-protocol.md#reproduction-and-retained-code-verification)
for the exact prerequisites.

## Reproduction and verification

Run from the repository root with the existing R environment and accepted
packages under the shared working directory:

~~~sh
BASE=/home/alex/projects/lidar_tree_benchmarks/work
Rscript scripts/run_teak_comparison_workflow.R MODE=packet \
  BASE="$BASE" OUT="$BASE/teak-comparison-workflow-output/packet-final"
Rscript scripts/run_teak_comparison_workflow.R MODE=preflight \
  BASE="$BASE" OUT="$BASE/teak-comparison-workflow-output/preflight-final"
Rscript scripts/run_teak_comparison_workflow.R MODE=packet \
  BASE="$BASE" OUT="$BASE/teak-comparison-workflow-output/packet-final" VERIFY=1
Rscript tests/run_tests.R
rumdl check --no-cache .
git diff --check
~~~

Generation requires a fresh output directory; verification recomputes and
checks existing outputs without rewriting them. The protocol documents the
separate future evidence-bundle and comparison invocation. Current templates
are deliberately insufficient for real scoring.

A blocked `MODE=compare` preserves its gate report and exits with status 2,
including verification of an existing blocked run. `MODE=preflight` exits
successfully when it has produced a valid report, even if the study is
blocked. This distinction lets automation check readiness without treating a
blocked comparison as completed scoring.

The final packet verifies 2,806 input records and five implementation files,
and emits 16 payloads plus its receipt. The separate preflight emits two
payloads plus its receipt. Both passed replay. Independent checks rehashed
all inputs, code and outputs, confirmed all 480,000 image samples against
the native raster, and checked the 24 unchanged box rows and 16 pending tile
records. The 39,465 channel samples equal to 255 remain opaque.

| Accepted receipt | SHA-256 |
| --- | --- |
| `packet-final/receipt.json` | `703f1996e5fd5f521a5f9b5e880325fbb89a267fe87a6744c26e1981b9234db6` |
| `preflight-final/receipt.json` | `0cee0d20b12cf6bca5b661012a7cd9c74f3fc1a022ccce7306d7c2652b7ec07a` |

The final R suite passed, including 16 workflow tests with 82 assertions.
Three existing skips remain: the gated live FF3D fixture, the empty-LAS writer
limitation and unavailable Python `plyfile`. The restricted package-index
request produced the existing R-universe warning. Invented evidence exercises
the admitted comparator, empty outcomes, source lineage, review history,
registration, time ordering, clipping, pooled counts and tamper rejection.
The saved demonstration is explicitly marked synthetic and supplies no real
human review or accuracy evidence.

Python verification ran 152 tests across the existing GPU and raster
environments: 150 passed and two optional upstream-source fixtures were
skipped. All 17 new historical-replay tests passed. The accepted smoke replay
preserved 2,757 run-file hashes, 193 sealed code hashes and the shared attempt
claim. The completed native reserve and development-consensus products also
passed their public-entry-point parent/output replay from the new checkout.

Five real CLI checks confirmed normal checkout `work/` output support,
blocked comparison and replay exit status 2, rejection of an existing output
and rejection of output under `scripts/`. Blocked replay preserved output
bytes and modification times. Three independent Sol reviews covered science,
contracts and operations; Astra implemented and rechecked their findings.
README workflows, requirements and result links were updated. Repository-wide
Markdown lint and whitespace checks passed. No detector inference was repeated.
