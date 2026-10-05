# Data and code availability

This page holds the draft availability statement for the benchmark paper and
the evidence behind it: where every input comes from, under which licence, and
what the archive will and will not redistribute. The archive DOI is recorded
here and in the README when the deposit is made, which is the last step before
submission. Licences and DOIs below were checked against DataCite, Zenodo,
Hugging Face and the GitHub licence API on 2026-10-02, and the camera-imagery
DOI against the NEON release API on 2026-10-05.

## Draft statement

> All field, airborne LiDAR and camera data are public data products of the
> National Ecological Observatory Network (NEON), released under CC0 1.0:
> vegetation structure (DP1.10098.001, RELEASE-2026,
> [doi:10.48443/pypa-qf12](https://doi.org/10.48443/pypa-qf12)), the
> discrete-return LiDAR point cloud (DP1.30003.001,
> [doi:10.48443/5ts2-rc92](https://doi.org/10.48443/5ts2-rc92)) and the
> camera imagery mosaic (DP3.30010.001,
> [doi:10.48443/8vq2-s021](https://doi.org/10.48443/8vq2-s021)) from the 2021
> flights over SJER, SOAP, TEAK, WREF and ABBY. The frozen evaluation clips,
> field-stem references, plot populations, per-cell results and persisted
> detections, checkpoint hashes and container image IDs are archived at
> Zenodo (DOI to be assigned at deposit), with a script that rebuilds every
> table from the archive. The code is available at
> <https://github.com/devakellc/lidar-tree-benchmark> under the MIT licence;
> the archive records the commit it was staged with. Third-party models are
> used under their own licences and are not redistributed; the archive lists
> their sources, versions and SHA-256 hashes so that every run can be repeated
> with the same weights.

## Inputs

| Component | Source | Licence | Version pin | In the archive |
|---|---|---|---|---|
| Field stems | NEON vegetation structure DP1.10098.001, [doi:10.48443/pypa-qf12](https://doi.org/10.48443/pypa-qf12) | CC0 1.0 | RELEASE-2026 (`neon_ground_truth.R`) | Derived stem tables and plot populations |
| Point clouds | NEON discrete-return LiDAR DP1.30003.001, [doi:10.48443/5ts2-rc92](https://doi.org/10.48443/5ts2-rc92) | CC0 1.0 | 2021 flights; all 80 tiles match RELEASE-2026 by size and CRC32C | Frozen clips with per-file SHA-256 (clip manifest) |
| Camera imagery | NEON high-resolution orthorectified camera imagery mosaic DP3.30010.001, [doi:10.48443/8vq2-s021](https://doi.org/10.48443/8vq2-s021) | CC0 1.0 | RELEASE-2026, 2021 flights, 79 tiles (NEON citation files) | Tile extents and the optical arms' box caches |
| Native QL2 cross-check | USGS 3DEP Entwine point tiles | US public domain | EPT resource per AOI | Derived results only |
| FGI-EMIT comparison | [doi:10.5281/zenodo.19351234](https://doi.org/10.5281/zenodo.19351234) | CC BY-NC-SA 4.0 | Zenodo record | Not redistributed; scores only |

## Models and software

| Component | Source | Licence | Version pin | In the archive |
|---|---|---|---|---|
| Benchmark code | This repository | MIT | Commit per table | Source snapshot |
| treeiso (vendored) | `external/treeiso` | MIT (treeiso, cut-pursuit); LGPL 2.1 (matlas_tools) | Vendored copy | Included with the code |
| ForestFormer3D code | [SmartForest-no/ForestFormer3D](https://github.com/SmartForest-no/ForestFormer3D) | CC BY-NC 4.0 | Commit `6a75c37` with local patch; build files in `gpu/forestformer3d-sm120` | Image ID only |
| ForestFormer3D weights | [doi:10.5281/zenodo.16742708](https://doi.org/10.5281/zenodo.16742708) | GPL-3.0-or-later | `epoch_3000_fix.pth` | SHA-256 only |
| SegmentAnyTree | [SmartForest-no/SegmentAnyTree](https://github.com/SmartForest-no/SegmentAnyTree) | MIT | Commit `a3561ed`, `PointGroup-PAPER.pt` | Image ID and SHA-256 |
| TreeisoNet (TreeAIBox) | [NRCan/TreeAIBox](https://github.com/NRCan/TreeAIBox) | CC BY-NC 4.0 | Commit `5380dde`; weights in `gpu/CHECKSUMS.sha256` | SHA-256 only |
| DeepForest | [weecology/deepforest-tree](https://huggingface.co/weecology/deepforest-tree) | MIT | Revision `cc21436`, deepforest 2.1.0 | Revision |
| Detectree2 | [doi:10.5281/zenodo.15863800](https://doi.org/10.5281/zenodo.15863800) | CC BY 4.0 (weights); MIT (code) | `250312_flexi.pth` | SHA-256 only |
| SAM2Point | [ZiyuGuo99/SAM2Point](https://github.com/ZiyuGuo99/SAM2Point), SAM 2 weights | Apache-2.0 | Commit `e6897a7`; `sam2_hiera_large.pt` baked into the image | Image ID and SHA-256 |
| lidR, lasR, lidRplugins | r-lidar, Jean-Romain/lidRplugins | GPL-3.0 | lidR 4.3.2; lasR pre-devel `34a79f0`; lidRplugins `567592a` | Versions and commits; pinned in `reproduce/Dockerfile` |

Two licences need care. ForestFormer3D code and TreeAIBox are
non-commercial (CC BY-NC 4.0), and FGI-EMIT is CC BY-NC-SA 4.0. The archive
therefore holds hashes, image IDs and download instructions for them, not the
files. The ForestFormer3D weights carry a different licence (GPL-3.0-or-later)
from its code; the statement cites both sources.

The LiDAR tiles were downloaded with `byTileAOP`, which takes no release pin.
On 2026-10-02 all 80 local 2021 tiles (SJER 13, SOAP 7, TEAK 18, WREF 21,
ABBY 21) were found in the RELEASE-2026 file lists from
`neon_released_files()`, with equal sizes and CRC32C checksums. NEON's
listing drops leading zeros from the checksum. The statement can therefore
cite the RELEASE-2026 DOI for the point clouds.

## Archive and reproduction

The archive is staged with `scripts/stage_archive.sh` and described in the
[archive guide](reproduction-archive.md). `scripts/reproduce_paper_tables.sh`
rebuilds every table of the frozen-clip benchmark from it on CPU and checks
each rebuilt file against the archived copy; `reproduce/Dockerfile` gives the
clean-machine environment. [model-provenance.json](model-provenance.json)
records the checkpoint hashes, image IDs and source commits taken from the
final runs' manifests and weight files. The GPU images were built locally
from the files under `gpu/` and are identified by image ID, as they are not
in a registry.

## Before the deposit

- Replace "DOI to be assigned at deposit" with the Zenodo DOI here and in the
  README.
