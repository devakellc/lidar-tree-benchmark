# Historical TEAK comparison workflow

This workflow prepares a review packet, checks evidence for a separately
frozen historical development study, and provides a dormant crown-box
comparator. It processes only TEAK_043. The eleven reserved plots remain
unadmitted; this historical model-observed plot cannot become an independent
holdout. The existing [canopy policy](teak-canopy-scoring-protocol.md) remains
unchanged. No real accuracy score is available from the current evidence.

## Commands and current outputs

Use the existing R environment with `terra`, `sf`, `png`, `jsonlite`,
`digest` and the pinned `clue` 0.3.68 solver. From the checkout root:

```sh
export CLAUDE_JOB_DIR=/home/alex/projects/lidar_tree_benchmarks/work
Rscript scripts/run_teak_comparison_workflow.R \
  MODE=packet BASE="$CLAUDE_JOB_DIR" \
  OUT="$CLAUDE_JOB_DIR/teak-comparison-workflow-output/packet-final"
Rscript scripts/run_teak_comparison_workflow.R \
  MODE=preflight BASE="$CLAUDE_JOB_DIR" \
  OUT="$CLAUDE_JOB_DIR/teak-comparison-workflow-output/preflight-final"
```

`BASE` defaults to `CLAUDE_JOB_DIR`, then the checkout's `work/`. It contains
the accepted canopy-policy, canopy-reference, native-pilot, acquisition-timing,
mosaic-compatibility and detector-smoke packages in their existing documented
subdirectories. It also contains the original native L3 RGB tile. The script
pins all six receipt hashes and verifies every advertised derived output,
linked source declarations and the full original RGB file. Hashing a reserved
preview does not decode its pixels. Only the TEAK_043 image core is decoded.

`OUT` must be fresh and separate from protected inputs, code and evidence.
Fresh directories under the checkout's `work/` are supported. Repeat the same
command with `VERIFY=1` to recompute every output and receipt and compare
bytes without rewriting the accepted output directory. Library/runtime
temporary-file behavior is not part of this guarantee. Changed code,
package versions, evidence or output bytes invalidate replay. Failed runs do
not acquire a success receipt; the receipt is written last. Unknown or
repeated command arguments are errors. A blocked `MODE=compare` writes its
preflight/receipt and exits with status 2, including during `VERIFY=1`. A
completed blocked preflight report exits with status 0.

The packet contains the following files:

- `original_rgb.png`: the complete 400 by 400 native uint8 RGB core, with no
  markings, resampling, scaling of color values or transparency. All values
  of 255 remain opaque. The target is the original L3 tile, whose decoded
  core equals the published image; the published TIFF's 255 nodata masking
  is not used.
- `numbered_boxes.svg`: the same embedded PNG with all 24 original numbered
  published boxes; `original_boxes.csv` preserves their stable keys,
  original geometry, edge/overlap flags and source identity.
- `review_packet_manifest.json` and `START_HERE.md`: scope, provenance and
  instructions to review the whole image before any prediction diagnostic.
- Blank versioned review, tile, registration, timing, checkpoint, adapter
  and admission templates. Generated templates are never human evidence.
- `preflight.json` and `preflight.csv`: every current gate, its state,
  evidence path/hash and the next required evidence. Current status is
  `blocked`; no TP/FP/FN, rates or positive admission flag is emitted.

Current parent integrity and native input/density gates pass. Reference and
whole-image review are pending; registration, temporal agreement and
checkpoint exposure are unknown; crown adapters are unsupported and paired
crown outcomes have not run. CHM treetops and the neural arms' sparse point
extents are not visible-canopy crown boxes. They are never overlaid in the
packet. Prior model observation is disclosed; reviewer prediction exposure
must be recorded individually rather than assuming blinding.

## A future frozen evidence bundle

Copy templates into a new directory and preserve the packet unchanged.
Complete actual human review and independent source work outside this
software. Use `admission_manifest.json` as the bundle entry point. Its
SHA-256 is a separate command argument, so changing or resealing the bundle
requires an explicitly selected new revision:

```sh
Rscript scripts/run_teak_comparison_workflow.R \
  MODE=preflight BASE="$CLAUDE_JOB_DIR" \
  BUNDLE=/absolute/path/to/frozen-evidence ADMISSION_SHA256=<sha256> \
  OUT="$CLAUDE_JOB_DIR/teak-comparison-workflow-output/reviewed-preflight"
Rscript scripts/run_teak_comparison_workflow.R \
  MODE=compare BASE="$CLAUDE_JOB_DIR" \
  BUNDLE=/absolute/path/to/frozen-evidence ADMISSION_SHA256=<sha256> \
  OUT="$CLAUDE_JOB_DIR/teak-comparison-workflow-output/admitted-comparison"
```

The manifest fixes `schema_version=1`, `status=frozen`, the claim
`historical_development_diagnostic`, all parent receipt hashes, the exact
TEAK_043 support object from the template, `reference_revision`, limitations,
and exactly the three declared arms. Support includes plot/image/spatial
group, role, 400 by 400 pixel footprint, affine transform, EPSG:32611,
original image/native/annotation hashes and an empty exclusions list. Each
arm repeats exactly the same support and revision. Other plots, groups,
roles, hidden exclusions and independent validation claims are rejected.

`artifacts` is a named object mapping IDs to `path`, `bytes` and `sha256`.
All paths are relative to the bundle and cannot traverse directories or use
symlinks. Required IDs are `whole_image_review`, `reference_review`,
`tile_review`, `registration`, `registration_ties`, `timing` and `exposure`.
Per-arm artifact IDs are referenced from that arm and its adapter record.
`evidence` is a separate named object of file records with `supplied_by`,
`verified_by` and `kind`: `human_attestation`, `independent_measurement`,
`production_record` or `review_record`. Every decision's `evidence_id` must
resolve to verified bytes and its reviewer must match that record's verifier.
Attachments remain human-interpreted source evidence; a hash authenticates
bytes, not the claimed contents, human identity, independence or inspection.

### Reference revision and whole-image review

`whole_image_review` is JSON following its template. Set `origin` to
`human_supplied` only for an actual supplied review. Required fields include
revision, reviewer, supplier, explicit UTC review start/completion times,
method, prediction
exposure (`yes`, `no`, `unknown`), an attestation evidence ID, and authenticity
`self_attested_not_independently_authenticated`. Every box and tile timestamp
must fall within that declared review interval. Whole-image completeness,
unboxed canopy, ambiguous vegetation and edge truncation must each be
`resolved`, with a rationale. Software cannot establish that those claims
are true merely because the fields are populated.

`reference_review` is CSV. Keep exactly one operation for each original key
and preserve its `original_*` geometry. Choose `keep`, `edit` or `remove`;
`keep` repeats the original bounds. New crowns use distinct `added:*` keys,
no original key, and `add`. Record proposed bounds, discovery tile, explicit
edge/overlap/split-merge/vegetation decisions, uncertainty note, rationale,
evidence, reviewer and UTC time. Pending or unresolved decisions block
admission. Removed originals remain in the revision history. All retained
references must be finite, positive-area boxes inside the full image.

`tile_review` is the fixed sixteen 100 by 100 pixel tiles, including all
unboxed space. Each row requires `status=reviewed`, an actual observation,
evidence and reviewer/time. `linked_keys` uses semicolon-separated revision
keys. An addition must be linked from its discovery tile and geometrically
intersect that tile. A completed table establishes structural coverage only;
it cannot prove exhaustive human review or crown completeness.

### Registration, timing and checkpoint conditions

`registration` JSON declares a measurement method, evidence/reviewer, an
explicit criterion-freeze time preceding measurement time and reference
review, at least three ties, span of at least 100 pixels in each image axis,
and positive maximum residual/combined-uncertainty limits. These timestamps
are attestations whose supporting records need human verification.

`registration_ties` CSV retains accepted and rejected features. Use distinct
stable-ground features, not crowns, detector output or mosaic-colored points.
Allowed independent methods are `surveyed_ground`, `lidar_geometry` and
`lidar_intensity`; each needs description, date stability, evidence and
reviewer. Rejections need reasons. `rgb_x_px` and `rgb_y_px` are continuous
coordinates from the top-left pixel edge; pixel centers are `n + 0.5`.
LiDAR coordinates and both uncertainties are in projected metres.

Accepted features must be in the core, separated by more than one RGB pixel
and 0.1 m in LiDAR, and noncollinear in both sensors: convex-hull areas must
exceed one square pixel and 0.01 square metre. The runner applies the fixed
image affine, reports residual vectors, combines uncertainties by root sum
of squares, and checks the declared limits without fitting any shift. The
geometry checks cannot authenticate independence, stability or measurement
quality. If defensible ground features are unavailable, registration stays
unknown and scoring remains blocked.

This bounded implementation supports only `temporal_route=conditional_historical`.
The `timing` record uses that route, `status=reviewed_conditional`, full-image
coverage, a reviewer/evidence ID, rationale and explicit limitations. RGB
exposure and exact lag remain `unknown`, with temporal agreement `unverified`.
It does not authenticate a production source map or provide an exact-date
admission route; that would require a separate spatial source-map validator.

`exposure_route=conditional_development` is required. The exposure CSV has
all eight neural arm/phase rows: pretraining, training, tuning and model
selection for both exact checkpoint identities. Each row distinguishes
`unknown`, `known_exposure` or `verified_non_exposure`, with rationale and
evidence/reviewer. Unknown exposure must remain a limitation. No choice can
make this historically used plot an independent test.

### Frozen crown adapters and source-instance accounting

Each arm declares checkpoint identity, frozen smoke configuration artifact,
exact source artifact, prediction CSV, adapter JSON, outcome and support.
The source hash must equal its sealed smoke output: CHM raw treetops or the
neural normalized prediction cloud. Configuration hashes and both neural
checkpoint hashes must also match. All artifacts are rehashed before use.

The adapter JSON requires a reviewed `visible_canopy_crown_boxes` target,
`crown_geometry` input, construction rule, code artifact, validation artifact,
boundary and lineage artifacts, reviewer/evidence, the fixed affine/CRS, and
`reference_consulted=false`. Its declared freeze time must precede the start
of reference review. This is a later crown adaptation task, not permission
to rename the
current diagnostic point extents or invent a fixed width around a treetop.

The structured validation JSON uses status `reviewed_crown_boundary_adapter`,
method, limitations, reviewer/evidence and `reference_consulted=false`.
Its `sha256` object binds `code`, `config`, `source`, `prediction`,
`boundaries` and `lineage` artifact bytes. It records the reviewed relationship
between code, inputs and outputs; this runner does not execute arbitrary
adapter code or independently authenticate its scientific validation.

The lineage CSV accounts for every frozen retained source instance with
`source_prediction_id`, `source_membership_sha256`, `status`, `box_id` and
`exclusion_reason`. IDs and membership hashes are derived from the pinned
neural diagnostics; CHM membership is SHA-256 of the source-file hash, a colon
and its treetop instance ID. `boxed` rows map one-to-one to prediction IDs;
`excluded` rows require explicit reasons. Omissions and invented IDs fail.
All dispositions are exported; exclusions cannot disappear from reporting.

Predictions use unique `id` and `source_prediction_id` plus finite positive
`xmin,ymin,xmax,ymax` pixel-edge bounds. Boundary CSV rows contain `id`,
sequential `vertex`, `x` and `y` for each non-self-intersecting positive-area
crown polygon. The runner recomputes each box from those retained vertices.
Unchanged neural sparse-point extents explicitly reject, even if their
metadata is relabelled. A superficial coordinate change does not establish
crown validity: actual independent adapter review remains necessary. Polygon
geometry and file hashes cannot establish it alone.

Preflight validates all geometry, source membership and outcomes before
admitting scoring. `completed_empty` requires an empty prediction table and
explicit source dispositions; `completed` requires predictions. Missing,
failed, unsupported or not-run arms block the paired comparison. The
comparator consumes exactly the rows validated by preflight.

## Comparison semantics and verification

The pure comparator reuses the frozen canopy policy's geometry, positive-area
clipping, inclusive IoU thresholds and stable maximum-cardinality-then-IoU
assignment. It retains the primary 0.5 and sensitivity 0.4 rows separately,
without threshold selection or changes to the stem matcher. Every positive
image intersection is scored; outside predictions are counted separately.

Admitted outputs include per-arm counts, matched IDs/IoUs, outside IDs,
source dispositions, reviewed reference and registration residuals. Explicit
empty predictions give zero TP/FP and FN equal to reference count. Undefined
rates stay missing. Paired support/revision must match; pooling sums counts
before rates. TEAK_043 remains one descriptive development cell, not an
estimate of generalization or concurrent-canopy accuracy: unknown RGB timing
remains a condition on historical box agreement. Current blocked outputs
contain no accuracy
numbers. Neither admission nor comparison modifies any parent artifact.

Run `Rscript tests/run_tests.R`. Invented fixtures exercise the complete
admission/comparison path, while the real packet and preflight remain blocked.
Tests cannot substitute for the human reference, independent measurements or
validated crown adapters that are still missing.
