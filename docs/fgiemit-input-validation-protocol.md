# FGI-EMIT Development Input Validation

Declared on 2026-09-23, following the fixed
[development split](fgiemit-development-protocol.md). Read point records only
for its ten development plots. Reserve and historical-test clouds are hashed
for integrity but never parsed, prepared, inferred or scored. Preserve the
original declaration and all previous artifacts. Write a new output directory;
an existing or failed attempt must not be overwritten.

## Point Identity and Support

Verify every source hash against the declaration before preparation. Require
finite coordinates, valid original return numbers, semantic classes 0–5,
nonnegative integer instance IDs and agreement with the published per-tree
metadata and category totals. Instance IDs are unique within each plot only.
Keep coincident coordinates as separate original rows.

The [release description](https://doi.org/10.5281/zenodo.19351234) defines class 5
as excluded partial trees. Retain every other row, including non-tree points
and buildings, vehicles and poles. Retain annotated edge trees and dead trees;
do not filter them by their flags. Check that class 1 corresponds to positive
instance IDs. Preserve original annotations in a separate reference file.

Model input contains geometry, original return numbers and a zero-based
`source_row` identifier only, with classification reset to unclassified.
There are no reference instance IDs, semantic labels or spectral attributes
in the model input. Reopen exports and require exact source integer XYZ,
scales, offsets, return fields and row identity. All controls must eventually
be scored on this same retained support; no annotation-assisted classes 2–4
removal is admitted by this preparation.

## Local Frame and Density

Use a distinct `FGI-EMIT/19351234/plot_<ID>` local metric frame per source file.
Preserve source coordinates and declare no EPSG or cross-plot transform. The
[dataset paper](https://arxiv.org/html/2511.00653v1#S3.SS3) describes cylindrical
plots in metres. Check source extents and report the retained XY footprint.
Local Z remains local elevation until terrain subtraction.

Measure first-return and all-return counts on the retained original rows.
Divide each by the area of their XY convex hull, saving its vertices. This is
an explicit observed-footprint density convention, not a recovered census
boundary. The hull spans interior gaps; report it beside the rounded published
area. Do not discard coincident returns or equate first-return counts with
independently verified emitted pulses. The release combines three scanners.

## Ground and Height Diagnostic

Run the existing lidR CSF defaults on all retained geometry, explicitly setting
`last_returns=FALSE` so the ground candidate set matches the historical bridge
that supplied placeholder return numbers. Preserve the true return fields.
Use the existing TIN normalization and its default `knnidw(3, 1, 50)` edge
extrapolation. Set one lidR thread and a 600-second limit per plot; record
failures and continue the remaining declared development plots without
changing parameters or replacing plots.

Require at least ten classified ground points, unchanged row IDs and XY,
finite normalized heights and finite nonnegative terrain-model coverage
statistics. Report ground counts, negative-height fractions, points outside
the ground XY convex hull, and maximum per-tree AGL versus published height.
These height differences compare different estimators and are diagnostics,
not detector metrics or independent terrain validation. The publication's
heights use local non-tree minima and an outlier rule; class 0 is not a pure
ground reference. Do not clip negative heights or relabel buildings as ground
from their original annotation.

## Provenance and Admission

Record the exact installed checkpoint, image and source identities for the
candidate deep-learning arms. Inspect serialized checkpoint metadata without
executing pickle payloads or loading a model. Compare available release and
training configuration evidence; distinguish documented dataset provenance
from an exhaustive plot-level overlap proof. Unresolved overlap stays unknown.

No inference, confidence calibration, detector selection or reserve evaluation
is authorized by this protocol. Valid exports and finite normalization do not
establish terrain accuracy, checkpoint independence, common score semantics or
resource feasibility for model inference. Keep overall admission false and
report remaining gates. No reference heights may become model inputs.
