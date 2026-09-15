# Frozen transfer audit runtime note

Declared on 2026-09-15 before retrying native-path inference. The original
[scientific protocol](frozen-transfer-audit-protocol.md) remains unchanged.

The first native-path attempt on training plot 1001 exhausted the 32 GB GPU
when `torch.cdist` requested 28.56 GiB with 27.06 GiB free. Four complete
cylinders were saved, but the plot had no complete prediction or score.
The failed run and original implementation manifest are retained under
`work/external/fgiemit/audit/native-memory-failure/`.

The retry sets the existing model's nearest-neighbor **row batch** (`chunk`)
from 20,000 to 2,048. This bounds allocation for the same reference points,
Euclidean distances, and first-minimum selection. It does not subsample points,
alter voxels, change weights, change score gates, or select new parameters from
performance. A synthetic test compares batched and unbatched nearest-neighbor
indices, including duplicate-coordinate ties. Floating-point reproducibility
across GPU kernels is not claimed.

The retry writes a fresh implementation manifest under `audit/corrected/`.
Failed outputs are not reused as successful plot predictions.

## Empty scene return

The memory-bounded attempt completed both corrected arms on plot 1001, then
stopped at the first cylinder of plot 1019. Upstream had written all 52,854
points with instance label -1 and score -1, then assigned `None` to a typed
`PointData` property, which raised an assertion. The saved scene was verified
with the existing container's PLY parser.

The next retry handles only that exact assertion, only after the full-scene
file exists and passes count/order/coordinate validation, and only if every
exported label is background. Other assertions, malformed output, or assigned
labels still fail. The interrupted attempt is retained separately under
`audit/native-empty-return-failure/`. Both plots are rerun under one final
implementation manifest; earlier successful cells are not silently relabeled
as outputs of the new driver. No thresholds or selection criteria change.
