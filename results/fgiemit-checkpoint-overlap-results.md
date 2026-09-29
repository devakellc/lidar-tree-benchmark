# FGI-EMIT Checkpoint Overlap and Policy Decision

Reviewed on 2026-09-25 after the complete development comparison and
50-fold calibration. Freeze **ForestFormer3D as the single-model candidate**
for apex detection and instance delineation, with the existing native pipeline
and fixed instance filters. Retain CHM-VWF and SegmentAnyTree as controls.
No probability threshold, fusion or new model fitting is selected. The
[frozen policy](../docs/fgiemit-frozen-policy.md) defines the next comparison.

The public evidence strengthens dataset-level provenance but does not prove
the exact weights' complete training history. Keep upstream overlap unknown.
Any eventual reserve result must remain a conditional within-dataset policy
evaluation; it cannot be labelled independent unseen-data validation.

## Identity and Evidence

The installed FF3D checkpoint SHA-256 is
`01037a648596832238ac72ea2f5eef87ceaf5aeb399e56ff4b760ba1ed1c777e`.
It matches the member of the
[official weight archive](https://zenodo.org/records/16742708), whose published
MD5 is `553d67379331966509076f3fbb409e57`. The release is dated 2025-08-05.
The native source revision is
`6a75c3735e4a4108d02ee944a8b93177f2360a4f`. The
[input provenance audit](fgiemit-development-input-results.md) already verified
these identities without loading a model; the policy replays that chain.

SAT's installed checkpoint SHA-256 is
`0b4d74b4644e37a16f59008ad0f5c62894fc4d2d906f3abd803bbfc5b5dd803a`.
The [pinned upstream LFS pointer](https://github.com/SmartForest-no/SegmentAnyTree/blob/a3561ed8447bbb7938f059ba65a3e9c97d6e2ee9/model_file/PointGroup-PAPER.pt)
still matches it. Embedded SAT metadata names `TreeinsFusedDataset` and a
sparsified-training directory. Neither this directory name nor the checkpoint
metadata contains a complete authenticated plot history.

The [FF3D paper](https://openaccess.thecvf.com/content/ICCV2025/papers/Xiang_ForestFormer3D_A_Unified_Framework_for_End-to-End_Segmentation_of_Forest_LiDAR_ICCV_2025_paper.pdf)
describes training on FOR-instanceV2. Its
[supplement, Table 1](https://openaccess.thecvf.com/content/ICCV2025/supplemental/Xiang_ForestFormer3D_A_Unified_ICCV_2025_supplemental.pdf)
lists training regions in Norway, Czech Republic, Australia, New Zealand,
Austria and French Guiana. Finland is absent from that table. Wytham Woods
and LAUTx are additional test-only datasets there. This is published
dataset-level evidence, not an authenticated list of all exposures of the
installed checkpoint.

The [SAT paper, Materials](https://arxiv.org/abs/2401.15739) describes training
with FOR-instance ULS, Norwegian MLS and synthetically sparsified versions.
Its FOR-instance sites are in Norway, Czech Republic, Austria, Australia and
New Zealand. This supports a different documented source population from
FGI-EMIT, but does not identify every training exposure of the installed LFS
artifact or conclusively map it to one reported training scenario.

The [FGI-EMIT paper](https://arxiv.org/html/2511.00653v1#S3.SS1) locates its
plots in Espoonlahti, Espoo, Finland. The authors describe their own DL
benchmark training from scratch on FGI-EMIT. Those experiments must not be
conflated with this repository's original upstream pretrained artifacts.
The [pinned FGI release](https://zenodo.org/records/19351234) is dated
2026-04-11 and its training archive and plot-metadata checksums still match
the original local declaration. Release chronology alone cannot prove absence
of earlier private access, pretraining or unrecorded fine-tuning.

## Why the Overlap Flag Remains Unknown

The remotely fetched
[committed FF3D split lists](https://github.com/SmartForest-no/ForestFormer3D/tree/6a75c3735e4a4108d02ee944a8b93177f2360a4f/data/ForAINetV2/meta_data)
exactly match the previously inspected revision: 47 train, 16 validation and
28 test entries. None names FGI-EMIT. Names alone cannot rule out renamed or
cropped inputs. Moreover, the paper's BlueCat region is absent from all three
lists. This discrepancy prevents treating these lists as an exhaustive
checkpoint training manifest; it is not evidence that FGI-EMIT was included.
The working copies were rewritten by historical inference and are not used
as training evidence.

No source reviewed supplies an exhaustive, checkpoint-bound record of
training, pretraining, validation-based model selection and subsequent
fine-tuning, together with a spatial/plot crosswalk to FGI-EMIT. Accordingly,
the finding is **no documented overlap found, absence unproven**. Published
geographical separation makes overlap less plausible; that is an inference,
not a cleared independence gate. The original provenance receipt remains
unchanged rather than being rewritten with a stronger claim.

The local reserve can still test choices frozen in this repository. Its
future claim is explicitly conditional on unresolved upstream exposure.
Reserve preparation and execution must independently pass their structural
and resource contracts. The policy freeze does not admit inference and reads
no reserve point records. The original 1003/1010/1023 reserve is retained;
no previously observed historical-test plot becomes a replacement holdout.

## Frozen Decision and Remaining Work

FF3D has the stronger observed development apex F1 (0.8091 versus 0.7323 SAT
and 0.5132 CHM) and mask F1 (0.7133 versus 0.6125 SAT) on equal support.
The selection uses those complete development counts, not reserve outcomes.
The calibration study does not establish a validated probability cutoff, so
retain every prediction passing the existing fixed filters. This provides a
concrete single-model policy without assuming an ensemble benefit.

The prospective plan contains nine detector cells and fifteen primary scoring
cells over all 257 reserve references. It preserves native-density methods,
the two scoring targets, height diagnostics, background and all reference
categories. Plot 1023 has 5,510,572 source points according to the original
header audit, larger than any development cloud. Keep the one-cell resource
limit and stop-on-failure rule; do not thin, replace or omit this plot.

The next implementation is reserve input validation and a separately sealed
execution contract in a fresh job root outside the development data root.
Keep the original audit replayable: it deliberately rejects reserve processing
artifacts inside that root. A successful policy freeze is not proof that the
larger scene fits the GPU or that reserve annotations/AGL have been validated.

## Reproduction and Verification

Ten primary-source files are archived locally, with URLs, retrieval times,
byte counts and SHA-256 hashes in
[`fgiemit-overlap-sources.json`](../docs/fgiemit-overlap-sources.json).
These include the two papers, FF3D supplement, FGI paper, two release metadata
responses, three committed split lists and the SAT LFS pointer. Raw documents
remain ignored artifacts under `work/fgiemit-policy-verification/sources/`.
The source manifest identifies the exact bytes reviewed; regenerated mutable
API responses may differ and require a new evidence review.

Use the existing Python environment and the paths from the
[development calibration](fgiemit-development-calibration-results.md). Run
these commands from the repository root to create and replay the freeze
against the archived sources and sealed calibration directory:

```sh
EVIDENCE="$CLAUDE_JOB_DIR/fgiemit-policy-verification/sources"
POLICY="$ROOT/development_policy"
"$PYTHON" scripts/freeze_fgiemit_policy.py \
  --root "$ROOT" --calibration "$CALIBRATION" --evidence "$EVIDENCE" \
  --out "$POLICY"
"$PYTHON" scripts/freeze_fgiemit_policy.py \
  --root "$ROOT" --calibration "$CALIBRATION" --evidence "$EVIDENCE" \
  --out "$POLICY" --verify
```

Creation requires a fresh directory and complete sealed parents. The tool
reads existing development metrics and source
metadata; it does not run models, fit calibration or parse reserve points.
The original dirty checkout and all previous receipts remain preserved.

The real freeze completed under `work/external/fgiemit/development_policy/`.
It seals four parent receipts/matrices, three code/protocol/source-manifest
files and two outputs, with execution disabled. Independent checks confirmed
the nine-cell order, all 257 references, unvalidated density fields, exact
parent/output hashes and preservation of the original 16 dirty files.
Read-only receipt replay passed through every prior development stage.

Full Python discovery passed: 65 tests, 63 passed and two optional upstream
checkout tests skipped. Focused regressions reject incomplete development
support, changed reserve membership/counts, prior processing, configuration
drift, altered source evidence, unsupported overlap claims and modified freeze
outputs. No R or GPU implementation changed, so their suites and live model
smokes were not rerun; the previous calibration report records that stage's
full R checks. README summaries, commands, requirements and indices are updated.
