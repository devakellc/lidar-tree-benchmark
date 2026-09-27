# Native FGI-EMIT ensemble pipeline results

The [pipeline](../docs/final-ensemble-pipeline.md) connects verified detector
outputs to explicit fusion comparisons, separate treetop/instance products
and count-pooled evaluation. Its default is the
[frozen FF3D policy](../docs/fgiemit-frozen-policy.md). The supported real-data
scope is the declared native FGI-EMIT population, with unknown upstream
checkpoint overlap and unverified independent AGL accuracy.

## Development comparison

All 30 sealed development cells were reused without inference. Independent
assembly scoring reproduced every single-arm TP, FP, FN and denominator.
The comparison uses all ten plots and 841 original annotated references.
Fusion uses the existing 2 m XY/5 m height-gated cross-arm clustering and
highest-point representative, with fixed membership and one vote per arm.

| Detection product | Predictions | TP | FP | FN | Precision | Recall | F1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| CHM-VWF | 375 | 312 | 63 | 529 | 0.8320 | 0.3710 | 0.5132 |
| SAT | 795 | 599 | 196 | 242 | 0.7535 | 0.7122 | 0.7323 |
| FF3D | 830 | 676 | 154 | 165 | 0.8145 | 0.8038 | 0.8091 |
| All-arm union | 871 | 578 | 293 | 263 | 0.6636 | 0.6873 | 0.6752 |
| Two-of-three consensus | 534 | 479 | 55 | 362 | 0.8970 | 0.5696 | 0.6967 |
| SAT/FF3D union | 845 | 594 | 251 | 247 | 0.7030 | 0.7063 | 0.7046 |
| SAT/FF3D consensus | 520 | 480 | 40 | 361 | 0.9231 | 0.5707 | 0.7054 |

These fixed fusion settings do not improve development F1 over FF3D. Consensus
raises precision while substantially reducing recall. Union is not guaranteed
to preserve a constituent detector's matches: the existing transitive
cross-arm clusters can join multiple nearby detections and keep only their
highest point. These are descriptive development comparisons, not a search
for the best possible fusion method or independent held-out fusion evidence.
No reserve outcome is used to alter the default.

Weighted all-arm fusion has complete calibration support on only two of ten
plots. The other cells are explicitly blocked by unavailable scores or
first-/all-return density outside the nine training plots' observed ranges.
No missing probability is clipped, imputed or silently dropped. The incomplete
candidate has no pooled primary score and is not promoted.

## Execution and product verification

The reserve run and final product verification are in progress. This section
will be completed from the sealed receipts before publication.
