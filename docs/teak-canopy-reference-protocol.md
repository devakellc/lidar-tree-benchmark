# TEAK published canopy-reference preparation

This workflow prepares existing human annotations for inspection before a
new LiDAR comparison. It follows the negative
[field-reference reconstruction](../results/teak-reference-support-results.md)
with a different reference population: canopy crowns visible in imagery.
It does not alter field support, run detectors or admit evaluation plots.

## Fixed scope and provenance

Use every named `TEAK_NNN_2018.xml` in the pinned NeonTreeEvaluation source
tree, together with the same-named RGB, CHM and LiDAR files: 18 plots in all.
This selection uses filenames and annotation availability, not model scores.
Tile-named TEAK annotations, other years, training archives and hyperspectral
payloads are outside this bounded package. Record this exclusion rather than
claiming all public TEAK annotations were screened spatially.

The [source manifest](teak-canopy-sources.json) records URLs, file identities,
sizes and SHA-256 hashes. Preserve downloaded originals. A pinned copy of the
parent audit's plot inventory supplies historical local-use flags. It is a
snapshot of that audit's scanned paths, not a fresh exhaustive exposure scan.
No absence flag establishes checkpoint independence or creates a holdout.

The DTA crown dataset is inventoried separately. Normalize its short TEAK
plot identifiers, retain source, individual and annotation-year fields, and
report repeated individuals. Algorithmic detections and fallback stem boxes
are not independent references. Hand-selected species crowns do not by
themselves establish a complete canopy census. Do not merge DTA rows with
NeonTreeEvaluation boxes by plot, year, proximity or count.

## Annotation and coordinate interpretation

NeonTreeEvaluation XML describes image-drawn canopy boxes. Preserve object
order and original pixel coordinates. Match XML filename, dimensions and
class to the paired image, rejecting malformed or out-of-image boxes.
Use the publisher's zero-origin pixel-edge convention: X increases from the
image left edge; Y increases downwards from the top edge. Convert edges
using the paired GeoTIFF resolution and extent, with the Y direction reversed.
Export projected boxes and image footprints in the image's EPSG:32611 frame.
The projected GeoJSON declares that CRS; consumers must honor it and must
not assume RFC 7946 longitude/latitude coordinates.

Images cover 40 by 40 m. Their visible-canopy annotation footprint is separate
from NEON's field-census footprint. A valid image extent does not resolve
missing field subplot corners. Image boxes do not supply stem positions,
apex coordinates, heights, accurate crown outlines or manual 3D instances.
Do not reuse height-gated stem scoring with invented box-centre apices.

Read every paired LiDAR clip without dropping points or altering its CRS,
return fields, labels or coordinates. Inventory missing CRS, invalid return
metadata, numeric XY extent departures, Z range and background labels.
Report stored point counts per RGB area as a diagnostic only. Native `frdens`
and `pdens` remain unknown until native acquisition and point preservation
are verified. Do not infer a LAS CRS from nearby RGB coordinates or repair
return metadata by guessing. The supplied `label` field is derived by
projecting image boxes onto points, with acknowledged boundary errors;
it cannot serve as independent 3D mask truth. Zero-labelled points remain
in the audit. Export positive-point and unique-positive-label counts separately
from XML-box counts; their correspondence remains unknown even when counts
match. Record both raster extents and CHM-minus-RGB bound offsets. Unequal
footprints alone do not quantify image-content registration error.

## Review and admission

The generated previews are aids for reviewing existing published labels.
They are not a model-blind reannotation task and do not prove agreement from
a second annotator. No human verification is manufactured by this workflow.
The review queue starts with all checks pending and split unassigned.

Before any comparison:

1. Establish exact installed-checkpoint training and model-selection exposure,
   including pretraining, fine-tuning and reuse of the same biological plots.
   Historical local-use plots remain development diagnostics. Decide whether
   unresolved upstream exposure permits only a conditional diagnostic claim.
2. Obtain provenance-backed native ALS from the contributing acquisition for
   the same image footprints, preserving original fields and sufficient
   surrounding context. Identify the original RGB and LiDAR flight dates and
   verify temporal agreement with RGB and CHM before choosing a native flight;
   the 2018 annotation filename does not establish the LiDAR acquisition year.
   Verify metric CRS, above-ground normalization, coverage and measured
   first/all-return density. Document registration against the images.
3. Review canopy completeness, ambiguity and image-edge trees independently
   of detector outputs. Declare an edge policy, uncertainty exclusions and
   the intended visible-canopy population before scoring.
4. Freeze spatial groups, whole-plot development/evaluation roles, the exact
   box-based matching policy and equal model support before detector output
   inspection. Pool counts under this repository's policy. Do not silently
   inherit the publisher's per-image average or replace stem matching.

If those gates cannot be met, use the material for annotation-method
development only. Deployment validation still needs representative user
tiles with independently verified references. Their paths, native density
and acquisition compatibility have not been supplied. Genuine 3D mask
validation remains a separate reference task.

## Reproduction

Run from the repository root with the existing R environment; `xml2` is
also required for the published XML. The script uses the shared path helper.
`CACHE` contains the source archive; `OUT` must be new and separate from it.

```sh
Rscript scripts/prepare_teak_canopy_reference.R \
  CACHE=/home/alex/projects/lidar_tree_benchmarks/work/teak-canopy-reference/sources \
  OUT=/home/alex/projects/lidar_tree_benchmarks/work/teak-canopy-reference/replay-new
```

Optional `FETCH=1` retrieves missing public files from manifest URLs and
copies the pinned local inventory from its recorded path when available.
Existing hash-mismatched files are rejected, never overwritten. Public API
metadata may change; changed bytes require an explicit new audit, not a
silently accepted update. An independent checkout also needs the pinned
local inventory; it cannot recreate historical exposure from public data.

All source bytes are checked before use and again before completion. The
receipt records source/code/package identities and every generated output
hash. Outputs include pixel boxes, projected geometry, per-plot quality
inventory, DTA source inventory, review queue and 18 previews. Every exported
reference and queue row remains `evaluation_ready = FALSE`. Editing the
queue does not enable any scoring entry point.
