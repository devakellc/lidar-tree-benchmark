# Published TEAK canopy-reference package

Prepared 28 September 2026 after the
[field-reference reconstruction](teak-reference-support-results.md) failed
to establish an eligible new comparison. This package provides **734
published human-drawn canopy boxes across 18 TEAK plots**, with paired
images, diagnostic cloud inventories and review previews. It reduces the
need to start annotation from scratch, but does not yet establish a fresh
validation set for the ensemble.

The [preparation protocol](../docs/teak-canopy-reference-protocol.md) defines
this separate visible-canopy reference track. No model was run, split
assigned, accuracy metric calculated or existing field support changed.

## What was acquired and prepared

The pinned [NeonTreeEvaluation repository](https://github.com/weecology/NeonTreeEvaluation/tree/96b29d566ca7ea9f604de3e1235c503ab101cb8a)
contains 18 named TEAK 2018 XML annotations with paired RGB, CHM and LiDAR
files. Those 72 files total 17,008,915 bytes. Selection includes every named
TEAK 2018 annotation at that revision; tile-named annotations, other years,
hyperspectral files and large training archives were excluded. This is not
an exhaustive spatial audit of all public annotations.

The [publisher's methods](https://doi.org/10.1371/journal.pcbi.1009180)
describe annotation of canopy crowns visible in imagery. Its repository
includes standing dead trees and omits fallen trees. The annotations cover
the image footprint, separately from the sampled field-stem population.
The XML contains boxes, not exact crown outlines, apex heights or manual
point-by-point instance labels. Published LiDAR labels were derived by
projecting these boxes onto points; boundary errors are acknowledged.

All selected images are 400 by 400 pixels at 0.1 m resolution, covering
1,600 m² in WGS84 UTM zone 11N. The workflow validates XML identity and bounds
and exports pixel boxes, projected boxes, image footprints and one labelled
preview per plot. Pixel-to-map conversion follows the pinned publisher
code's top-left origin and Y-axis reversal. Review is still pending; preview
generation is not independent human verification.

## Local overlap

The parent audit's pinned historical-use inventory separates the package:

| Local-use category | Plots | Published boxes |
| --- | --- | ---: |
| Historical benchmark use | 043, 044, 045, 046, 047, 050, 052 | 295 |
| Locally unobserved in the pinned inventory | 049, 051, 053, 054, 055, 057, 058, 059, 060, 061, 062 | 439 |
| Total | 18 | 734 |

All plot identifiers above have the `TEAK_` prefix. Changing sensor year does
not make the seven observed biological plots fresh holdouts. The other
eleven are candidates for further provenance review only. Placement in a
publisher's evaluation directory does not establish non-exposure of our
installed checkpoints. No exact checkpoint/training crosswalk was established
here. The seven distributed plots from the field-reference reconstruction
are not this package's 18 image-annotation plots.

## Paired cloud defects

The archived clips contain 175,475 points. **Every clip lacks LAS CRS
metadata and has inconsistent return fields.** Across the package, 71,283
rows have a return number greater than the recorded number of returns.
Do not infer valid pulse density, overwrite return counts or assign a CRS
from the RGB file without independent provenance.

These are processed benchmark clips. Their near-ground Z ranges and the
publisher's normalized-cloud description do not establish original native
ALS fields, independent AGL accuracy or deployment-compatible acquisition.
Stored point count divided by RGB area ranges from 4.126 to 10.133 per m²;
this is an archive diagnostic, not verified native `pdens` or `frdens`.
Both native density fields remain unknown in the output.

The numeric point coordinates place 243 points outside the paired RGB
extent. All 18 CHM and RGB extents differ, despite both declaring EPSG:32611.
The inventory preserves each extent and its signed CHM-minus-RGB offsets.
For TEAK_043, CHM bounds are 0.5 m west and 0.1 m south of the RGB bounds;
unequal footprints alone do not establish image-content registration error.
These differences remain explicit; the workflow neither crops points nor
forces raster alignment. Numeric coordinate proximity alone does not verify
registration. All raw background and tree labels remain in their original
files and counts; they are not filtered into a mask-evaluation population.
Positive-point and unique-positive-label counts are separate from XML counts.
For example, TEAK_051 has 51 positive labels versus 52 XML boxes. Even equal
counts do not establish an object-ID crosswalk: correspondence remains unknown.

## The second public crown source

The [Weecology DTA crown dataset](https://huggingface.co/datasets/weecology/neon-tree-crowns-dta/tree/20662f1b6848032269f11360666d411037c79073)
was downloaded as a 27.5 MB GeoPackage and inventoried separately. Its TEAK
records contain:

| Source | Rows | Interpretation |
| --- | ---: | --- |
| Algorithmic | 727 | Model detections or stem-buffer fallbacks; not independent labels |
| Hand-drawn boxes | 183 | 2019 imagery; 75 rows on locally used plots and 108 on locally unobserved plots |
| Hand-drawn polygons | 293 | 68 distinct individuals across 2018, 2019, 2021, 2023 and 2024 |

All polygon rows belong to TEAK_001, TEAK_043, TEAK_046 or TEAK_047, which
already have local benchmark use. Repeated years do not supply 293 separate
trees or fresh biological plots. These species-linked crowns do not prove
a complete plot census. They are not joined to the image boxes; plot/year
agreement does not establish individual identity or equal reference support.
In particular, the 2018 polygon subset has 56 rows: 17, 23 and 16 for plots
043, 046 and 047, compared with 24, 39 and 36 XML boxes. This is a selected
reference population, with no established individual crosswalk to the XML.

## Decision and concrete next step

Keep the 18-plot package as a reviewable canopy-reference starting point.
The 11 plots with 439 boxes and no recorded local use are the first candidates
for exact checkpoint-exposure review and provenance-backed **native NEON ALS
retrieval from the contributing acquisition**. Identify the original RGB and
LiDAR flight dates and verify temporal agreement with RGB and CHM before
selecting a native flight. The 2018 annotation filename does not establish
the LiDAR acquisition year. Acquire matching cloud footprints with context
and verify return fields, height normalization, density and image registration
before running detectors. This preparation does not authorize a claim that
those candidates form an independent held-out set.

Do not use the publisher's derived LiDAR labels for manual 3D mask claims,
or the DTA algorithmic crowns as independent truth. Manual review must settle
canopy completeness, ambiguous crowns and image-edge policy. A future
box-based comparison needs its own declared matching and whole-plot split;
the existing height-gated stem score cannot simply accept box centres.
The intended user clouds remain unavailable, so target density and transfer
are still unmeasured. Native FGI-EMIT evidence remains conditional and separate.

## Reproduction and verification

Use [the preparation entry point](../scripts/prepare_teak_canopy_reference.R)
and the command in the protocol. The
[source manifest](../docs/teak-canopy-sources.json) pins 86 source files,
including public methods and the historical local inventory. Original
annotations retain publisher attribution and the source archive includes
the NeonTreeEvaluation license; the DTA card states CC-BY-4.0.

The local package lives under `work/teak-canopy-reference/`. Generated files
remain ignored working artifacts. Code-only checkouts do not contain the
source payloads or historical local inventory. Receipt hashes distinguish
source data, executable code and derived outputs. The accepted `final-run`
and separate `final-replay` each verified 86 source files, four executable
files and 24 outputs. All 25 package files, including the receipt, reproduce
byte for byte. Existing output directories and corrupted source bytes were
also rejected by entry-point checks.

Three independent reviews covered scientific eligibility, primary sources
and reproducibility. Confirmed fixes include readable preview labels,
explicit raster offsets and point-label counts, and acquisition wording
that does not infer a flight year from an annotation filename. No review
admitted model evaluation or claimed independent human relabelling.

The full R suite passed, including 35 focused preparation assertions.
Three skips remain: optional live FF3D inference, an empty-LAS writer
fixture limitation and unavailable Python `plyfile`. The environment emitted
its restricted-network R-universe index warning and a libxml compiled/runtime
version warning. No Python/GPU code changed and no detector smoke ran.
Repository-wide Markdown lint, whitespace checks, source/document links and
the complete publication diff passed. README priorities and workflow entries
were updated. The original checkout's 16 dirty paths remained byte-identical.
