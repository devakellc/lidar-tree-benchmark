# TEAK visible-canopy box comparison policy

This declaration prepares the published TEAK canopy references for a future
comparison. It follows the [native input pilot](../results/teak-native-pilot-results.md)
and fixes geometry, spatial reservations and matching before new predictions
are inspected. The [machine-readable policy](teak-canopy-policy.json) binds
the exact parent packages. No real prediction input or scoring entry point is
provided by this preparation step.

## Reference population and review

The reference population is the 734 published image boxes across 18 named
TEAK plots. Preserve each image identifier, object index and original pixel
edges. These are image-visible canopy annotations, not measured tree stems,
apices, accurate crown outlines or independent 3D masks. Keep the historical
height-gated stem scorer and its inputs unchanged.

Audit every box's distance to the image edge, literal boundary contact,
proximity within one pixel and proximity within 2 m. Flag duplicate geometry
and overlapping boxes for inspection. These are reproducible geometry checks;
overlap alone does not identify an annotation error, and a flag does not
exclude or validate a crown. No density or model-score threshold selects
references, plots or review outcomes.

Review the complete image, including areas without boxes, without seeing
detector outputs. A reviewer must resolve omitted crowns, split or merged
crowns, ambiguous vegetation and boundary truncation. Record their identity,
evidence and adjudication in a separate versioned reference revision. This
package leaves human review pending. AI inspection of the historical pilot
is a diagnostic observation, not independent human verification.

An unresolved completeness or edge-ambiguity question blocks the whole plot
from real TP, FP, FN and rate calculation. Do not score only the reviewed
boxes while treating the surrounding unreviewed image as negative space.
Do not silently correct original annotations; any revision needs a new
source identity and review before predictions are examined.

## Image support and edge policy

The support is the full 40 by 40 m image, distinct from field-census support.
Pixel edges have origin at the upper left; X increases rightwards and Y
downwards. The paired image binds their conversion to metric EPSG:32611.
Both arms must supply axis-aligned boxes in this common frame. An adapter
must document how its predicted crown instances produce those boxes and
preserve instance identity. A treetop alone is not a predicted crown box.

Keep all 734 published boxes unchanged in this audit. A future admitted
reference revision must freeze every adjudicated addition, removal and
correction before predictions are examined; it must retain the original
box identities and decision history. Clip predicted boxes to the image
footprint and retain every positive-area intersection, including partial
crowns at the boundary. Count predictions with no positive-area intersection
separately as outside support. Reject non-finite, reversed or zero-area input
boxes before clipping. Do not add an arbitrary area floor, shrink boxes,
shift coordinates or expand predicted points into boxes using references.

Edge flags are reported separately; they do not create ignore regions or
automatically remove predictions or references. After admission, unmatched
duplicates and overlapping predictions count as FP. A crossing or oversized
prediction cannot escape FP through a small overlap with an ignored crown,
because this policy has no ignored-crown region. Clipping changes the target
to agreement on the visible part inside the image, not complete crown shape.

## Matching and reporting

Use box intersection over union (IoU) at **IoU >= 0.5** as the primary rule.
Choose a global one-to-one assignment that first maximizes the number of
eligible pairs and then their total IoU. Stable reference and prediction IDs
are sorted before assignment so input row order cannot resolve ties.
Declare **IoU >= 0.4** as a fixed sensitivity analysis; do not select the
better threshold after viewing results or mix thresholds when pooling.

The [publisher's method](https://doi.org/10.1371/journal.pcbi.1009180)
describes a threshold above 0.4, selecting the highest-IoU prediction for a
reference and averaging image-level rates. Our primary threshold, global
assignment and pooled counts are intentional study choices. Results must
identify that difference; they are not a reproduction of the publisher's
headline score. The existing distance/height stem matcher is a different
task and is not replaced by this box matcher.

For each admitted plot and fixed threshold, report TP, FP, FN, reference and
prediction counts, outside-support counts and all failures/exclusions. Pool
counts before calculating precision, recall or F1. Require identical admitted
plots, reference revisions, image support and native inputs across arms.
A completed empty prediction has TP = FP = 0 and FN equal to the reference
count. Precision is undefined; recall is zero when references exist. If both
populations are empty, precision, recall and count-based F1 are undefined.
Missing or failed output is unknown and blocks the comparison. Undefined
rates remain unknown.

The implementation in this change exercises box matching on synthetic
fixtures only. Those counts establish software behavior, not TEAK accuracy.
They cannot satisfy the admission conditions below.

## Whole-plot reservations

Use only image extents and the pinned historical-use inventory to assign
roles. The seven previously used plots are development plots. The eleven
other candidates are reserved but unadmitted: no validation or test split
is activated and no checkpoint independence is asserted. They were already
downloaded and inventoried, so they are not a pristine blinded dataset.

Expand each image rectangle by the fixed 25 m inference context on all
sides. Link touching or overlapping context rectangles and take transitive
components; the smallest plot ID names each component. Component members
must stay together in any later split. A component containing historical
use is entirely development-only. Plot roles cannot be changed by editing
a generated review queue.

Report core and context distances, with 100 m and 200 m context-gap grouping
as spatial sensitivity diagnostics. These distances do not establish an
ecological decorrelation range and do not change the frozen reservation.
Preventing shared inference points is weaker than statistical independence.
All plots remain one TEAK acquisition setting, not independent sites or
evidence of general transfer to the user's USGS-like clouds.

## Admission and reproduction

Before real comparison, bind independently reviewed reference completeness
and edge decisions, native input coverage and density, timing/registration,
frozen model/checkpoint/configuration identities, crown-to-box adapters and
equal arm support. Resolve training and model-selection exposure, or declare
a separate conditional diagnostic study that cannot claim independent
generalization. The present policy authorizes neither mode of real scoring.

Run from the repository root using the existing R environment with `sf`,
`terra`, `jsonlite`, `digest` and `clue` 0.3.68. The solver version is pinned
for repeatable tie handling; no new model environment is needed.

```sh
Rscript scripts/prepare_teak_canopy_policy.R \
  PACKAGE=/home/alex/projects/lidar_tree_benchmarks/work/teak-canopy-reference/final-run \
  PILOT=/home/alex/projects/lidar_tree_benchmarks/work/teak-native-pilot-output/final-run \
  OUT=/home/alex/projects/lidar_tree_benchmarks/work/teak-canopy-policy-output/run-new
Rscript tests/run_tests.R
rumdl check --no-cache .
git diff --check
```

Both input packages must be present and match their pinned receipts. The
script verifies their generated payloads and manifest links; it does not
claim to recheck their original remote sources or redownload archives. The
output directory must be new and separate from both packages. Preserve
failed attempts, use a fresh output for retries, and keep generated data
outside version control. Only the historical TEAK_043 image is rendered for
visual inspection; other plots contribute geometry and metadata only.
