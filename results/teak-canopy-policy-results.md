# TEAK canopy-reference review and comparison policy

The published TEAK package now has an explicit
[box comparison policy](../docs/teak-canopy-scoring-protocol.md): retain the
full image footprint and partial edge crowns, use one-to-one box IoU matching,
pool counts and preserve whole-plot spatial groups. This prepares a future
visible-canopy comparison; it produces no real detector scores or eligible
evaluation plots.

The metadata audit covers all 734 boxes on 18 plots. Seven historically used
plots remain development plots. The other eleven are reserved but unadmitted,
with no independent holdout claim. Exact checkpoint exposure remains unknown
for both installed models, as established in the
[native pilot](teak-native-pilot-results.md). Human reference review, timing
and registration also remain unresolved.

## Geometry review

All original object indices and pixel edges survive into the review queue.
There are 62 boxes touching an image boundary, 106 within one pixel and 250
within 2 m. These nested counts describe edge proximity, not three separate
populations. Across plots, 180 pairs overlap with positive area, involving
300 distinct boxes. No two boxes in the same image have identical geometry.
Overlap is a review flag, not evidence of a duplicate tree.

| Plot | Boxes | Touch boundary | Within 1 pixel | Within 2 m | Role |
| --- | ---: | ---: | ---: | ---: | --- |
| TEAK_043 | 24 | 3 | 5 | 11 | Development |
| TEAK_044 | 36 | 1 | 2 | 11 | Development |
| TEAK_045 | 39 | 4 | 6 | 18 | Development |
| TEAK_046 | 39 | 3 | 4 | 14 | Development |
| TEAK_047 | 36 | 3 | 6 | 9 | Development |
| TEAK_049 | 25 | 0 | 1 | 8 | Reserved; unadmitted |
| TEAK_050 | 48 | 4 | 8 | 20 | Development |
| TEAK_051 | 52 | 4 | 6 | 13 | Reserved; unadmitted |
| TEAK_052 | 73 | 2 | 2 | 17 | Development |
| TEAK_053 | 20 | 1 | 3 | 7 | Reserved; unadmitted |
| TEAK_054 | 31 | 6 | 6 | 12 | Reserved; unadmitted |
| TEAK_055 | 19 | 1 | 1 | 9 | Reserved; unadmitted |
| TEAK_057 | 60 | 2 | 9 | 23 | Reserved; unadmitted |
| TEAK_058 | 35 | 3 | 6 | 12 | Reserved; unadmitted |
| TEAK_059 | 72 | 3 | 10 | 19 | Reserved; unadmitted |
| TEAK_060 | 45 | 9 | 15 | 20 | Reserved; unadmitted |
| TEAK_061 | 41 | 6 | 8 | 14 | Reserved; unadmitted |
| TEAK_062 | 39 | 7 | 8 | 13 | Reserved; unadmitted |

The full per-box inventory retains geometry flags separately from human
adjudication. Every human review status remains pending. No flag changes the
reference population, and no model output was used to select boxes or roles.

## Historical pilot visual triage

Only TEAK_043 was visually inspected for this step. Its 24 published boxes
include three touching the image boundary and five within one pixel. The
numbered panel pairs the native RGB crop with the unchanged published boxes.
Objects 5, 7 and 13 meet the right or bottom boundary; objects 1 and 15 sit
one pixel from the left or top. These cases require a decision about the
visible crown fragment before the whole image can support a score.

AI inspection also found unboxed vegetation-like patches whose interpretation
cannot be settled from RGB appearance alone. They could represent vegetation
outside the intended canopy population or a reference omission. No new tree
label, count correction or automatic exclusion is inferred. This is a
model-blind diagnostic on an already-used plot, not independent human
adjudication. The other candidate images were not visually inspected here.

## Spatial reservations

The fixed 25 m context on each side of every 40 m image produces 17 connected
components. Only TEAK_049 and TEAK_060 share context: their rectangles overlap
by approximately 0.3 by 1.0 m. They must stay in the same future split. There
is no direct context overlap between historical and reserved plots.

That geometric separation does not establish independence. The nearest
reserved/historical context gap is only 30.2 m. Wider gap diagnostics connect
additional plots; a 200 m context-gap rule joins 17 of the 18 plots. No
ecological decorrelation distance has been established, and these plots share
one site and acquisition setting. The frozen 25 m grouping only prevents
shared inference context across roles.

The eleven reserved candidates have 439 published boxes. They have already
been downloaded and inventoried. Reservation protects them from new tuning
in this workflow; it does not undo prior exposure or certify upstream model
independence. No calibration, validation or test split is activated.

## Scoring contract

The primary future threshold is IoU >= 0.5, with IoU >= 0.4 declared in
advance as sensitivity analysis. Assignment maximizes match count first and
total IoU second, with one prediction and one reference per match. This
deliberately differs from the publisher's threshold and per-image averaging;
the protocol records that distinction. The existing height-gated stem
matcher is unchanged.

Predicted crown boxes will be clipped to the same full image footprint.
Every positive-area intersection remains eligible, including partial edge
crowns. Invalid boxes fail before clipping; outside predictions are counted
separately. There are no automatic edge exclusions or ignored-crown regions.
An unresolved edge or completeness question keeps the entire plot unscored,
including TP/FP/FN. This avoids treating unreviewed canopy as negative space.

The executable preparation consumes no real predictions. Synthetic matching
tests establish the declared geometry and assignment behavior only. They do
not measure TEAK performance, fix model thresholds, or authorize evaluation.

## Verification and next use

The [preparation entry point](../scripts/prepare_teak_canopy_policy.R) consumes
the two pinned parent packages and emits per-box review rows, per-plot roles
and pending checks, all 153 spatial pairs, the historical review panel, a
synthetic assignment fixture, a summary and a receipt. The accepted outputs
are `final-run` and `final-replay` under `work/teak-canopy-policy-output/`.
Use the command in the protocol with a fresh output directory to reproduce.

Each run verifies five direct inputs, five executable files, all 38 outputs
advertised by the parent receipts and six new generated payloads. All seven
files, including the receipt, are byte-identical between runs. This verifies
the prepared parent packages and linked manifests; the original remote
source payloads were not reread or reacquired in this step. An independent
metadata calculation agrees with the per-plot counts and spatial distances.
Every original value in all 734 source box rows is preserved.

Three Sol reviews covered the scientific target, spatial reservations and
software contracts. Astra fixed empty-prediction handling, duplicate plot
declarations, unsupported independence flags and contradictory policy text.
The final full R suite passed, including 80 focused assertions. Three known
checks were skipped: opt-in live ForestFormer3D, an empty-LAS fixture the
installed writer cannot create, and Python PLY reading without `plyfile`.
The environment emitted its inaccessible R-universe package-index warning
and a libxml compiled/runtime version warning. No GPU inference was run.
No Python code changed.

Entrypoint checks rejected an existing output directory, an output inside
an input package and a corrupted parent payload before creating output.
Repository-wide Markdown lint, whitespace and local document-link checks
passed. The complete change was reviewed against its intended base. README
now records the policy, workflow entries and eligibility limits. Generated
artifacts remain outside Git, and hashes confirm the original checkout's
16 pre-existing changed files are unchanged.

The package is ready for independent annotation adjudication and future
adapter-contract work. It provides no real accuracy result. Every human
review remains pending, every evaluation flag remains false and no reserved
plot was used for detector development in this step.
