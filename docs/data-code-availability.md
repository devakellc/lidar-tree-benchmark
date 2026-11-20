# Data and code availability

This page holds the draft availability statement for the benchmark paper and
the evidence behind it: where every input comes from, under which licence, and
what the archive will and will not redistribute. The archive DOI is recorded
here and in the README when the deposit is made, which is the last step before
submission. Licences and DOIs below were checked against DataCite, Zenodo,
Hugging Face and the GitHub licence API on 2026-10-02, and the camera-imagery
DOI against the NEON release API on 2026-10-05.

## Draft statement

> All field, airborne LiDAR and camera data of the benchmark are public data
> products of the National Ecological Observatory Network, released under
> CC0 1.0:
> vegetation structure (DP1.10098.001, RELEASE-2026,
> [doi:10.48443/pypa-qf12](https://doi.org/10.48443/pypa-qf12)), the
> discrete-return LiDAR point cloud (DP1.30003.001,
> [doi:10.48443/5ts2-rc92](https://doi.org/10.48443/5ts2-rc92)) and the
> camera imagery mosaic (DP3.30010.001,
> [doi:10.48443/8vq2-s021](https://doi.org/10.48443/8vq2-s021)), from the 2021
> flights over SJER, SOAP, TEAK, WREF and ABBY. The cross-sensor check also
> uses public-domain USGS 3DEP point clouds. The fixed evaluation clips,
> field-stem references, plot populations, per-cell results and persisted
> detections, checkpoint hashes and container image identifiers are archived
> at Zenodo (DOI to be assigned at deposit), with a script that rebuilds every
> table from the archive, the density-routing analysis included; the radius
> check of Section S18 and the ForestMamba run of Section S23 are not in the
> archive. The code is available at
> <https://github.com/devakellc/lidar-tree-benchmark> under the MIT licence.
> Third-party models are used under their own licences and are not
> redistributed; the archive lists their sources, versions and SHA-256
> hashes, and the repository lists ForestMamba's (Section S23). FGI-EMIT is
> available from its authors under CC BY-NC-SA 4.0
> ([doi:10.5281/zenodo.19351234](https://doi.org/10.5281/zenodo.19351234)).

## Inputs

| Component | Source | Licence | Version pin | In the archive |
|---|---|---|---|---|
| Field stems | NEON vegetation structure DP1.10098.001, [doi:10.48443/pypa-qf12](https://doi.org/10.48443/pypa-qf12) | CC0 1.0 | RELEASE-2026 (`neon_ground_truth.R`) | Derived stem tables and plot populations |
| Point clouds | NEON discrete-return LiDAR DP1.30003.001, [doi:10.48443/5ts2-rc92](https://doi.org/10.48443/5ts2-rc92) | CC0 1.0 | 2021 flights; all 80 tiles match RELEASE-2026 by size and CRC32C | Frozen clips with per-file SHA-256 (clip manifest) |
| Camera imagery | NEON high-resolution orthorectified camera imagery mosaic DP3.30010.001, [doi:10.48443/8vq2-s021](https://doi.org/10.48443/8vq2-s021) | CC0 1.0 | RELEASE-2026, 2021 flights, 79 tiles (NEON citation files) | Tile extents and the optical arms' box caches |
| Native QL2 cross-check | USGS 3DEP Entwine point tiles | US public domain | EPT resource per AOI, recorded with each cached clip | Cached per-plot clouds over SJER, SOAP and TEAK with their provenance sidecars, and derived results |
| FGI-EMIT comparison | [doi:10.5281/zenodo.19351234](https://doi.org/10.5281/zenodo.19351234) | CC BY-NC-SA 4.0 | Zenodo record | Not redistributed; the reports give its scores |

## Models and software

| Component | Source | Licence | Version pin | In the archive |
|---|---|---|---|---|
| Benchmark code | This repository | MIT | Commit per table | Source snapshot of the commit in `CODE_COMMIT`, deposited beside the archive |
| treeiso (vendored) | `external/treeiso` | MIT (treeiso, cut-pursuit); LGPL 2.1 (matlas_tools) | Vendored copy | Included with the code |
| ForestFormer3D code | [SmartForest-no/ForestFormer3D](https://github.com/SmartForest-no/ForestFormer3D) | CC BY-NC 4.0 | Commit `6a75c37` with local patch; build files in `gpu/forestformer3d-sm120` | Image ID only |
| ForestFormer3D weights | [doi:10.5281/zenodo.16742708](https://doi.org/10.5281/zenodo.16742708) | GPL-3.0-or-later | `epoch_3000_fix.pth` | SHA-256 only |
| SegmentAnyTree | [SmartForest-no/SegmentAnyTree](https://github.com/SmartForest-no/SegmentAnyTree) | MIT | Commit `a3561ed`, `PointGroup-PAPER.pt` | Image ID and SHA-256 |
| TreeisoNet (TreeAIBox) | [NRCan/TreeAIBox](https://github.com/NRCan/TreeAIBox) | CC BY-NC 4.0 | Commit `5380dde`; weights in `gpu/CHECKSUMS.sha256` | SHA-256 only |
| DeepForest | [weecology/deepforest-tree](https://huggingface.co/weecology/deepforest-tree) | MIT | Revision `cc21436`, deepforest 2.1.0 | Revision and SHA-256 of `model.safetensors` |
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
[archive guide](reproduction-archive.md); a source snapshot of the commit in
its `CODE_COMMIT` is deposited beside it, and the [rebuild
record](reproduction-rebuilds.md) lists its stagings and clean-container
rebuilds. `scripts/reproduce_paper_tables.sh`
rebuilds every table of the frozen-clip benchmark from it on CPU and checks
each rebuilt file against the archived copy; `reproduce/Dockerfile` gives the
clean-machine environment. [model-provenance.json](model-provenance.json)
records the checkpoint hashes, image IDs and source commits of every learned
arm. Those of ForestFormer3D and TreeisoNet come from the final runs'
manifests; the other arms wrote no run manifest, and theirs come from the
local images and weight files the runs used. The GPU images were built
locally from the files under `gpu/` and are identified by image ID, as they
are not in a registry.

## Open Forest Observatory catalogue

The [catalogue preflight](../results/ofo-preflight-results.md) read stem
maps of the Open Forest Observatory data catalog,
[doi:10.5281/zenodo.23402904](https://doi.org/10.5281/zenodo.23402904)
(published 15 October 2026), with public-domain USGS 3DEP point clouds. Its
decision was no-go for every plot group, so nothing from these plots is part
of the benchmark, of the draft statement above or of the archive. The
licences are recorded here because they bind any later use.

Each plot carries its own licence: a Creative Commons licence, or the
public domain for the 12 plots of `STEF2007` and `STEF2018`. Licence and
contributors are the same for every plot of a project. The catalogue asks
for attribution to the data contributors, not to the Open Forest
Observatory, and for an acknowledgment of the Open Forest Observatory as
the means of discovery and access. The plot-level list, with the licence of
each of the 225 plots, is the appendix of the preflight results.

| Project | Plots | Licence | Contributors | Required citation | Withheld from training | Reference tables redistributable |
| --- | --- | --- | --- | --- | --- | --- |
| CRBLDG2022 | 4 | CC BY 4.0 | Connie P. Ryan, Robert A. York, Brandon M. Collins, Ariel T. Roughton, Scott L. Stephens | — | 1 | yes |
| Cambria2021 | 28 | CC BY 4.0 | Dr. Sarah Bisbing, Conor Phelan | — | 0 | yes |
| DS2024 | 6 | CC BY 4.0 | Dr. Constance Harrington &  David Marshall (Pacific Northwest Research Station, U.S. Forest Service), Dr. Derek Young (UC Davis) | — | 1 | yes |
| EP2018 | 1 | CC BY 4.0 | JonahMaria Weeks, Dr. Derek Young, Dr. Hugh Safford | — | 1 | yes |
| Eshom2020 | 39 | CC BY 4.0 | Dr. Sarah Bisbing, Bryant Nagelson | — | 24 | yes |
| FOCAL2020 | 10 | CC BY SA 4.0 | Dr. Derek Young | — | 2 | no |
| FOCAL2022 | 4 | CC BY SA 4.0 | Dr. Derek Young | — | 2 | no |
| FOCAL2023 | 4 | CC BY SA 4.0 | Dr. Derek Young | — | 0 | no |
| FOCAL2025 | 4 | CC BY SA 4.0 | Dr. Derek Young | — | 0 | no |
| JLHZ2019 | 3 | CC BY 4.0 | James Lamping, Harold Zald | — | 0 | yes |
| MNPK2018 | 6 | CC BY 4.0 | Dr. Malcolm North, Max Odland, Dr. Paige Kouba | — | 0 | yes |
| NEON2023 | 62 | CC0 1.0 | National Ecological Observatory Network (NEON) | — | 0 | yes |
| OHDS2024 | 7 | CC BY 4.0 | Dr. Constance Harrington (Pacific Northwest Research Station, U.S. Forest Service), Dr. Derek Young (UC Davis) | — | 2 | yes |
| SJGEO2018 | 1 | CC BY 4.0 | Dr. Marko Spasojevic | Spasojevic, Marko et al. (2023). Data from: Integrating ontogeny and ontogenetic dependency into community assembly [Dataset]. Dryad. <https://doi.org/10.6086/D1267D> | 0 | yes |
| SSI2023 | 1 | CC BY 4.0 | Sierra Streams Institute; Erin Andrew | — | 0 | yes |
| SSMT2024 | 9 | CC BY 4.0 | Dr. Constance Harrington (Pacific Northwest Research Station, U.S. Forest Service), Dr. Derek Young (UC Davis) | — | 2 | yes |
| STEF2007 | 4 | Public domain | Knapp, Eric E.; Carlson, Robert L | Knapp, Eric E.; Carlson, Robert L. 2021. Stanislaus-Tuolumne Experimental Forest ‘Methods of Cutting’ study plots 8-11: 88+ years of forest composition. Fort Collins, CO: Forest Service Research Data Archive. <https://doi.org/10.2737/RDS-2021-0061> | 0 | yes |
| STEF2018 | 8 | Public domain | Alexis Bernal | Bernal, Alexis B.; Kane, Jeffrey M.; Knapp, Eric E.; Zald, Harold. 2020. Inventory and boundaries of stands treated with variable density thinning within Stanislaus-Tuolumne Experimental Forest. Fort Collins, CO: Forest Service Research Data Archive. | 0 | yes |
| TNC2023 | 24 | CC BY SA 4.0 | Dr. Derek Young (UC Davis), Ed Smith (TNC) | — | 5 | no |
| VP2022 | 51 | CC BY NC SA 4.0 | Vibrant Planet, PBC | Acknowledge Vibrant Planet, PBC | 14 | no |
| WADNR2023 | 11 | CC BY 4.0 | Derek Churchhill | — | 2 | yes |
| All non-NEON projects | 225 | CC BY 4.0 (116), CC BY NC SA 4.0 (51), CC BY SA 4.0 (46), Public domain (12) | — | — | 56 | 128 of 225 plots |
| Whole catalogue | 287 | CC BY 4.0 (116), CC BY NC SA 4.0 (51), CC BY SA 4.0 (46), CC0 1.0 (62), Public domain (12) | — | — | 56 | 190 of 287 plots |

Four points bind a later archive:

- Any derived or re-shared table must state, for each plot, a licence
  equivalent to or compatible with the plot's own, carry the metadata others
  need to understand and use it, and meet any other term of that licence.
- Derived reference tables may be redistributed only for plots under
  CC BY 4.0, CC0 or the public domain, with the attribution above and, where
  the licence names one, the required citation.
- For the share-alike projects (`TNC2023`, the `FOCAL` projects) and the
  non-commercial share-alike project (`VP2022`), an archive would hold plot
  shifts, cell definitions and tree identifiers only, with a script that
  rebuilds the tables from the catalogue record.
- Plots flagged `withhold_from_training` are reserved by the catalogue for
  model testing. Field points of this catalogue are part of at least one
  public training set for imagery models, so a learned arm needs its
  training data checked against the catalogue before it is scored on them.

Inputs of the preflight, with retrieval times and digests, are listed in
[ofo-preflight-sources.json](ofo-preflight-sources.json).

The [second preflight](../results/ofo-preflight-2-results.md) added three
kinds of public input, none of which enters the benchmark or the archive:
crown annotations of the NeonTreeEvaluation benchmark, with the camera
images and canopy height models they belong to (Weinstein and others, 2021;
CC0 1.0, repository `weecology/NeonTreeEvaluation` at one recorded commit);
NEON vegetation structure and discrete-return LiDAR of Niwot Ridge
(CC0 1.0), used only to test the registration; and fire perimeter records,
Forest Service activity records and the Forest Service surface-ownership
layer, from the interagency and Forest Service map services (US public
domain). They are listed in
[ofo-preflight-2-sources.json](ofo-preflight-2-sources.json).

## Before the deposit

- Replace "DOI to be assigned at deposit" with the Zenodo DOI here and in the
  README.
