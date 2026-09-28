# External validation dataset eligibility audit

Reviewed 28 September 2026 using public metadata and primary documentation.
This is a dataset selection report, not a detector experiment or a declaration
of admitted evaluation support.

**Prioritize CedarCypress3D for structural preflight. Retain BorFIT as the
second candidate and Sepilok as a secondary ALS diagnostic. No candidate is
currently cleared for independent evaluation with the installed checkpoints.**
The recommendation concerns evidence quality and practical next steps; it does
not predict which dataset will produce favorable detector scores.

## Decision basis

The [native pipeline](../docs/final-ensemble-pipeline-v2.md) is integrated and
verified. Its [results](final-ensemble-pipeline-results.md) support a frozen
FF3D policy within the declared FGI-EMIT population. Those reserve plots have
now been observed, and the
[checkpoint audit](fgiemit-checkpoint-overlap-results.md) leaves upstream
training exposure unresolved. New data must support a distinct claim.

This bounded search follows primary dataset records, product guides and
papers for real forest ALS/ULS with individual-tree references. It includes
plausible multi-platform, semantic-only and synthetic alternatives to make
the exclusions explicit. It is not an exhaustive catalogue. Search terms
included `airborne lidar individual tree instance segmentation dataset`,
`BorFIT`, `CedarCypress3D`, `International benchmark ALS individual tree
segmentation`, `Lin3D` and `ForestScan`.

Priority is qualitative, in this order: genuine instance-reference suitability,
annotation/support clarity, ability to separate sites and plots, documented
input availability and compatibility, then relevant domain coverage. All
candidates retain an unresolved exact-checkpoint exposure gate. Public release
dates and different countries are useful evidence, not proof of independence.

Three statuses are distinct:

- **Preflight candidate:** enough documentation to prioritize further input
  and support checks; this does not admit acquisition or inference here.
- **Hold:** a concrete reference, provenance or compatibility gap must be
  resolved before the claimed evaluation can be declared.
- **Outside this comparison:** available labels or sensor conditions do not
  currently support the intended forest ALS/ULS instance comparison.

## Ranked shortlist

Published densities below are descriptive point-density figures. They are
neither measured retained-support `pdens` nor first-return `frdens` for this
pipeline. None establishes sparse-ALS transfer or clears the CHM density rule.

| Priority | Dataset and population | Published density and reference type | Access evidence | Decision and principal blocker |
| --- | --- | --- | --- | --- |
| 1 | [CedarCypress3D](https://zenodo.org/records/22168721): 34 plots at two Japanese plantation sites; 1,627 field-surveyed trees plus additional UAV-only annotations | UAV-LiDAR; site means 5,802 and 676 points/m²; manually reviewed UAV tree instances | Versioned Zenodo record; CC BY 4.0; one 3,002,103,950-byte archive listed | Preflight candidate. Resolve census/core/buffer handling, timing, return schema and AGL; exact checkpoint exposure remains unknown. |
| 2 | [BorFIT](https://doi.pangaea.de/10.1594/PANGAEA.980505): record reports 385 20 × 20 m clouds from 145 northern boreal sites | Manual tree instances in selected reference plots; record says about 1,200 points/m², product guide about 400 | Public PANGAEA record, guide and file links; CC BY 4.0 | Hold. Resolve repository scientific-validation warning, conflicting density descriptions and coverage/edge policy. |
| 3 | [Sepilok ALS benchmark](https://zenodo.org/records/7181101): one tropical 1 ha reference area | About 139 points/m²; TLS-derived ALS labels with manual quality ratings | Versioned CC BY 4.0 record; CSV labels and core-boundary files listed | Secondary diagnostic candidate. Establish confidence/ignore policy, raw-return provenance, height frame and exposure; one site cannot establish broad transfer. |
| 4 | [La Palma](https://zenodo.org/records/14051046): one 47 × 58 m pine reference plot, 24 trees | Study reports about 500 points/m²; manually segmented normalized cloud | Versioned CC BY 4.0 record; 37,574,271-byte archive listed | Small compatibility check only. No independent development/evaluation population within this one plot; verify normalization, return fields and point-label schema. |

Archive sizes and license identifiers were read from release metadata; archive
contents were not downloaded or inspected. Licenses require their stated
attribution. An accessible metadata record is not a successful bulk download.

## CedarCypress3D: first structural preflight

The [data paper](https://arxiv.org/html/2608.30149v1) documents 16 Saiki and
18 Kokonoe plots. Annotation was reviewed across annotators; Kokonoe used
watershed assistance. Field inclusion covers planted trees at all DBHs and
other species at DBH at least 10 cm. This is not a census of every small tree.
Saiki ALS precedes its census by two growing seasons; Kokonoe's measurements
are described as within the same growing season. The sites also differ in
sensor, terrain and species mix, so a site contrast would combine those effects.

The 1,627 count describes field-surveyed trees, not the complete annotated
population. Section 4.2 of the data paper identifies additional within-core
trees in Saiki plot 13 with no field-survey records. They received new UAV
`treeID` values. Their height and DBH were measured from the UAV point cloud
and supplied separately from the field datasheet.

Require a plot/tree-ID crosswalk distinguishing field records, these UAV-only
annotations and imputed attributes. Predeclare their eligibility separately for
manual mask scoring, field-linked apex scoring and height evaluation, with
support, exclusions and denominators reported for each target. An annotated
mask is not evidence of a field stem or independent height measurement.
Do not use UAV-derived heights as independent validation of heights from that
same cloud, or silently exclude unmatched IDs from the annotation population.

Clouds use anonymized local coordinates. The 12 m census radius sits inside an
18 m clip. `treeID=0` includes outside trees as well as non-tree points;
classification 1 denotes outside-plot support and classification 5 denotes
trees. **Reusing the FGI-EMIT class-5 exclusion would remove the reference
trees.** Some field-linked crowns cross the nominal core boundary.

Before any pilot, define which rooted trees and points are scorable, how to
ignore unreferenced vegetation, and how to retain context without counting
outside detections as false positives. Keep annotation-derived classes out of
model inputs and label-driven geometry selection. Verify return attributes,
coordinate units, vertical datum and normalization independently; translated
coordinates do not justify assigning an EPSG. Resolve field-linked apex
definitions and the imputed field height before height-based evaluation.

The [release record](https://zenodo.org/records/22168721) is dated
2026-08-30. It postdates the documented FF3D release, but acquisition predates
it; private exposure remains unproven. Two sites offer a possible site-held-out
design, not an already declared split. Plot overlap and spatial grouping must
be checked from metadata before assigning either site or any plot to a role.

## BorFIT: broader support, unresolved documentation

The [PANGAEA record](https://doi.pangaea.de/10.1594/PANGAEA.980505) describes
2021–2024 acquisitions in Yakutia, Canada and Alaska. It explicitly says the
dataset lacks final scientific validation because usual author approval was
not obtained. That warning prevents treating repository availability as an
annotation acceptance result. It also supplies return-number fields and
ground classification in its schema, which is promising but not verified on
point records. Species are partly classifier predictions; they are not all
independent manual species labels.

The [product guide](https://download.pangaea.de/reference/133868/attachments/Product%20Guide.pdf)
describes height-selected subplots within shared flight transects. Its density
description differs from the record; retain both values as unresolved, rather
than choosing one. Tree IDs 1 and 2 represent unclassified and ground points;
instances start at 3. Preserve original IDs and map background explicitly.

The guide specifies manual segmentation in reference plot codes `00`, `01`,
`05` and `10`. The number of eligible instance-labeled plots among the 385
released clouds is not verified from the archived documentation; do not use
385 as an admitted mask-scoring denominator.

Required next evidence is a version-specific plot/transect crosswalk, complete
instance and boundary policy, scientific-validation resolution, and CRS/height
documentation. Group all subplots from a shared site/transect during splitting;
385 clouds are not 385 independent sampling units. Ground labels alone do not
establish accurate AGL. No installed-checkpoint training crosswalk was found
in the reviewed documentation.

## Sepilok and La Palma: bounded secondary roles

The [ALS benchmark paper](https://doi.org/10.1016/j.jag.2023.103490),
Sections 2.2–2.4 and Table 1, describes Sepilok ALS from 2020 and TLS from
2017, registered with reported RMSE 0.192 m. ALS instance labels were
propagated from automatically segmented, manually checked TLS trees. They
are not direct manual segmentation of every ALS point. The published analysis
filters reference quality and uses crown-polygon scoring; those results are
not interchangeable with this pipeline's full-point IoU metrics.

A new protocol would need a fixed reference-quality/ignore rule, full input
support, epoch-change handling and source-row mapping before applying apex
or mask scoring. The small
[release README](https://zenodo.org/records/7181101/files/README.md)
documents alignment transforms but not a complete return/AGL schema. The
record's exposed payload lists CSVs and boundary files, not LAS files. Do not
infer that its introductory reference to raw data supplies first returns.

The paired Wytham ALS area has about 7 points/m² in Table 1 (6.26 in the
text), but Wytham's TLS population is already used in upstream model papers.
Changing sensor does not create an independent biological population.
Sepilok also appears in ForestScan; a crosswalk must prevent counting a
repackaged site or epoch as a new held-out dataset.

The [La Palma paper](https://doi.org/10.3390/drones8120772), Section 2.2,
links the released reference to the 24-tree Taburiente plot. Its separate
154-tree Garajonay field plot is not evidence of a second released manual
instance scene. A normalized input must not be normalized again. Verify the
retained ground/return fields and point labels before deciding whether all
three detector arms can share a compatible input. This small scene could
check an adapter later; it cannot support both tuning and an independent
site-level test by subdividing its trees.

## Other screened sources

| Source | Evidence and disposition |
| --- | --- |
| [FOR-instance](https://zenodo.org/records/8287792) and [FOR-instanceV2](https://zenodo.org/records/16742708) | These are documented training/development sources for SAT and FF3D respectively. Do not designate their training/validation support as fresh external evaluation. Publisher test splits require exact checkpoint/split verification and still represent the upstream benchmark family. |
| [Wytham TLS and LAUTx in FF3D](https://openaccess.thecvf.com/content/ICCV2025/papers/Xiang_ForestFormer3D_A_Unified_Framework_for_End-to-End_Segmentation_of_Forest_LiDAR_ICCV_2025_paper.pdf) | Published upstream test populations; useful for reproduction with appropriate claims, not fresh external validation merely because this repository has not scored them. [LAUTx](https://zenodo.org/records/6560112) is personal laser scanning and includes separate automatic and manual segmentation archives. |
| [ForestScan](https://essd.copernicus.org/articles/18/1243/2026/) | Rich tropical TLS/ULS/ALS and census collection, including Sepilok. The reviewed collection description does not establish a ready-to-score, manually verified instance label for every airborne point. Registration and label transfer would be a separate reference-construction study. Licenses/access conditions differ by component; census accessibility cannot be inferred from the LiDAR collection. |
| [DigiForests](https://www.ipb.uni-bonn.de/data/digiforest-dataset/) | The project explicitly assigns tree instances to backpack data and separately supplies UAV observations. Corresponding airborne instance labels are not established by that description. Requires an explicit airborne reference source; the stated dataset license is CC BY-NC-SA 4.0. |
| [Lin3D](https://github.com/bjfu-lidar/Lin3D-Large-scale-forest-scene-INterpretation-3D-point-cloud-dataset) | The public v0.2 schema is XYZ plus ground/lower-object/wood/foliage classes. Semantic classes are not individual-tree instance IDs. Outside the present mask comparison without additional references. |
| [Boreal3D](https://boreal3d.github.io/) | Simulated ALS/ULS/MLS/TLS with instance labels. Useful for controlled software or simulation studies; cannot establish transfer to real measured forests. |
| Existing FGI-EMIT and NEON studies | Historical outputs stay protected. Observed FGI reserve/test plots cannot become fresh evaluation. Nominal NEON plot boxes do not establish complete instance references. [HARV/BART remains retired](../docs/harv-bart-closeout.md); this audit does not reopen it. |

## Common admission gates and next deliverable

The evidence supports **documentation-level prioritization only**. No split,
detector run or calibration fit is declared by this report. A subsequent
CedarCypress3D structural preflight should produce an admission matrix with:

1. Versioned source inventory and checksums, physical plot/site grouping,
   overlap/buffer audit, and complete census inclusion and ignore rules.
2. An annotation-free model-input contract with a reversible point-row map;
   explicit background/instance mapping, a tree-ID/reference-source crosswalk,
   and separate mask, field/apex and height support with their denominators.
3. Verified units and height frame, normalization inputs and diagnostics,
   valid return provenance, then separately measured `frdens` and `pdens`.
   If returns cannot be recovered, the current three-arm comparison stays
   blocked; do not substitute total point density for first-return density.
4. Exposure evidence tied to the exact installed FF3D and SAT hashes, including
   pretraining, training, validation/model selection and later fine-tuning,
   with dataset aliases and spatial crosswalks. The existing split lists are
   non-exhaustive, so an absent name cannot clear this gate.
5. A proposed whole-site/plot split, inference limits and separate apex/mask
   metrics frozen before outcomes are inspected. Any output-side masking or
   reference exclusions must be explicit and consistent across all arms.

If upstream exposure cannot be established, a prospective study could only
make a clearly qualified transfer claim; it cannot be renamed independent
validation. If scope must cover low-density ALS, these leading dense ULS
candidates do not satisfy that requirement. Simulated thinning would require
its own declared experiment and cannot stand in for native sparse acquisition.

This report recommends preflight of CedarCypress3D first. It makes no request
to authors, starts no acquisition, and leaves the installed models and frozen
policy unchanged. A split and bounded benchmark protocol follow only after
the relevant support and provenance decisions are resolved.

## Evidence and verification

The [source manifest](../docs/validation-dataset-sources.json) records public
URLs, retrieval times, byte counts and SHA-256 hashes. Raw documents are under
`work/validation-dataset-audit/sources/` in the shared working directory.
It distinguishes fresh retrievals from six unchanged documents/split lists
reused from the earlier checkpoint audit. Installed checkpoint hashes are
carried forward from that audit; weights were not loaded or rehashed here.

Twenty-one source files were archived and hash-verified. The archive contains
documentation and release metadata only: no LAS/LAZ, label CSV, model weights
or dataset archive was downloaded. The initial BorFIT paper retrieval exceeded
the 30 MB documentation cap; its record and product guide support this audit.
Two initial paper endpoints failed; the ALS paper was retrieved from a
coauthor's university repository and the La Palma paper from the publisher's
PDF endpoint. Failed attempts are retained in the manifest, not counted as
reviewed evidence. Published file checksums were inventoried, not validated
against undownloaded dataset payloads.

No scientific script or generated benchmark artifact changed. README links
and scope were updated. JSON/source hashes, local document links, the complete
diff, full repository Markdown lint and whitespace checks were verified.
R/Python suites and GPU smoke tests are not applicable to this documentation
change; no inference, calibration fitting or scoring was performed.
