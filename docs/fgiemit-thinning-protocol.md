# FGI-EMIT thinning protocol

Declared on 5 October 2026, before any thinned cloud was produced or any
detector run on one. On the FGI-EMIT development plots ForestFormer3D and
SegmentAnyTree lead CHM-VWF by 0.22 to 0.30 apex F1; on NEON at native
density the lead is about 0.05. Density, forest type and reference
completeness all differ between the two. This study thins FGI-EMIT to the
NEON ladder and scores against its true labels, so density is varied alone.

## Scope

- The ten development plots (841 reference trees). The evaluation reserve and
  the historical test plots are not read, and no path written by this study
  names a reserve plot. Outputs go outside the FGI-EMIT data root.
- A development diagnostic under the [frozen policy](fgiemit-frozen-policy.md):
  it makes no sparse-density claim for the frozen pipeline and changes no
  frozen choice.

## Density variants

- Targets: the five-site NEON medians, 9.8, 4.7, 2.5, 1.3 and 0.6 first-return
  pulses/m², plus each plot's native cloud (1,000–1,700 first returns per m²).
- Provider: seeded `homogenize` at 5 m on all returns, as the NEON frozen
  provider decimates. FGI-EMIT carries no verified pulse identifiers, so each
  plot's all-return target is the pulse target divided by its measured share
  of first returns. The seed is `seed_for("FGI-EMIT", plot, target)`; lidR runs
  single-threaded. The same retained rows make the model input
  (`geometry.las`), the labels (`reference.laz`) and the above-ground cloud
  (`normalized.laz`). Each variant's measured first-return density is
  reported.

## Arms and cells

- CHM-VWF with the NEON paper rule: CHM resolution 0.25 m at 8 or more first
  returns per m² and 0.5 m below, `a` = 0.10, 3 × 3 smoothing below 8
  (`detect_lasr` in `sweep_lib.R`). This replaces the development matrix's CHM
  rule, which is undefined below one first return per m².
- SegmentAnyTree and ForestFormer3D: the development matrix's images,
  checkpoints and whole-scene inputs, unchanged.
- 3 arms × 10 plots × 5 densities = 150 cells, run once each with a 3,600 s
  limit, stopping on the first failure. A run that finds no tree is a result,
  not a failure.

## Scores

- Apex F1 against the dense reference apexes (maximum above-ground point of
  each true tree), matched greedily within 4 m horizontally and 5 m
  vertically (`audit_apex_match`), as in the development matrix.
- Mask F1 at IoU 0.5 against the true labels on the retained points
  (`score_instance_cell`).
- Two post-processing rules for the learned arms, both reported: the
  development matrix's fixed filter (instances of at least 40 points and
  1.5 m vertical extent), and the NEON reduction, which keeps every instance
  whose top is at least 2 m above ground. The fixed filter was set for dense
  clouds and removes most crowns at the sparsest targets.
- Pooled by summed counts over the ten plots, with a paired whole-plot
  bootstrap (1,000 resamples, seed 20260923) of each arm's lead over CHM-VWF
  and of each density's change from native.

## Question and reading

If the learned arms' lead over CHM-VWF falls from about 0.25 at native density
to about 0.05 at NEON densities, density explains the FGI-EMIT and NEON
contrast. If the lead stays large, forest structure and reference completeness
explain it, and the paper reports the two datasets as a contrast, not a
controlled effect.
