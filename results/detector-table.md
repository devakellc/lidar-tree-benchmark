# Detector table

The twelve arms of the frozen-clip benchmark, as run for the paper. Hashes,
image IDs and commits are in [model-provenance.json](../docs/model-provenance.json);
licences and sources are in the
[data and code availability](../docs/data-code-availability.md) page. Training
data are as the sources state them, checked on 5 October 2026.

| Arm | Type | Input | Training data | Version and hash | Licence |
| --- | --- | --- | --- | --- | --- |
| CHM-VWF | Local maxima on a canopy height model, variable window | Normalized point cloud (first returns) | None; window and resolution from the literature and measured density | lasR `pre-devel` `34a79f0` | GPL-3.0 (lasR) |
| `multichm` | Local maxima over a stack of height-sliced CHMs | Normalized point cloud | None (lidRplugins defaults) | lidRplugins `567592a` | GPL-3.0 |
| `lmfauto` | Point local maxima, automatic window | Normalized point cloud | None (package defaults) | lidRplugins `567592a` | GPL-3.0 |
| `ptrees` | Multi-scale point segmentation (Vega et al. 2014) | Normalized point cloud | None (package example parameters) | lidRplugins `567592a` | GPL-3.0 |
| AMS3D | Adaptive mean shift in 3-D | Normalized point cloud | None (Ferraz et al. 2016 allometry) | crownsegmentr 1.0.1 | GPL-3.0 |
| Li 2012 | Point-cloud region growing (Li et al. 2012) | Normalized point cloud | None (lidR defaults) | lidR 4.3.2 | GPL-3.0 |
| ForestFormer3D | Transformer instance and semantic segmentation | Raw point cloud, whole scene | FOR-instanceV2 training split: ULS from Czechia, Norway, Austria, Australia, New Zealand and French Guiana, Norwegian MLS and Czech TLS; density of the training data not stated | `epoch_3000_fix.pth`, SHA-256 `01037a64…`; image `fd60f5cd…` | Code CC BY-NC 4.0; weights GPL-3.0-or-later |
| SegmentAnyTree | Sparse 3-D instance segmentation (PointGroup) | Raw point cloud | FOR-instance ULS (five countries) and Norwegian MLS, with copies sparsified to 10–1,000 points/m² | `PointGroup-PAPER.pt`, SHA-256 `0b4d74b4…`; commit `a3561ed`; image `27ce258d…` | MIT |
| TreeisoNet | 3-D tree localization and offset networks (TreeAIBox ALS models) | Normalized point cloud, 0.8 × 0.8 × 2.0 m voxels for apexes | UAV LiDAR (about 1,160 points/m²) of reclaimed wellsites near Grande Prairie, Alberta, as described with the TreeAIBox models; the link to these exact files is inferred from their names | `als_treeloc.pth` `c6e15a21…`, `als_treeoff.pth` `6cf5d890…`; commit `5380dde` | CC BY-NC 4.0 |
| DeepForest | RetinaNet crown boxes on RGB | NEON 10 cm camera mosaic, with apex heights from the native CHM | LiDAR-derived crowns from 22 NEON sites, then hand annotations from six NEON sites **including SJER and TEAK** | `weecology/deepforest-tree` revision `cc21436`; deepforest 2.1.0 | MIT |
| Detectree2 | Mask R-CNN crown polygons on RGB | NEON 10 cm camera mosaic, plot crops | Closed-canopy tropical forests (Harapan, Danum, Paracou, Sepilok) and urban Cambridge | `250312_flexi.pth`, SHA-256 `43b58544…` | Code MIT; weights CC BY 4.0 |
| SAM2Point | Promptable segmentation with 3-D prompts | Normalized point cloud, prompted with up to 40 CHM-VWF tops per plot | None in 3-D; SAM 2 trained on SA-1B and SA-V images and video | SAM2Point `e6897a7`; `sam2_hiera_large.pt` `7442e4e9…`; image `744e0b92…` | Apache-2.0 |

## Notes

- **DeepForest is not zero-shot at two sites.** Its retraining annotations
  include SJER and TEAK imagery, so its SJER and TEAK scores are not
  independent of the training sites. Its Washington and SOAP scores are.
- **Every learned point arm was trained on dense data.** ForestFormer3D and
  TreeisoNet on ULS, MLS or TLS at hundreds to thousands of points per m²;
  SegmentAnyTree alone added sparsified copies down to 10 points/m², which
  the NEON native clips exceed at the median (17.9 all-return points/m², 9.8
  first-return pulses/m²; two of the 106 adopted plots sit just under 10);
  the decimated rungs (8.4 points/m² and below) all fall under that floor.
- **Licence conflicts.** ForestFormer3D's code is CC BY-NC 4.0 while its
  checkpoint record is GPL-3.0-or-later; the paper cites both. TreeAIBox does
  not state a separate licence for its weights.
- The classical arms are training-free; their settings and when they were
  fixed are in the [configuration provenance](../docs/configuration-provenance.md).
- Wall time and memory per plot for every arm are in the
  [compute-cost table](compute-cost-results.md).
