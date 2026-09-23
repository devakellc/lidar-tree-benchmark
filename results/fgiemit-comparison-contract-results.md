# FGI-EMIT Development Comparison Declaration

Completed on 2026-09-23 under the
[comparison protocol](../docs/fgiemit-comparison-protocol.md). The declaration
freezes **30 detector cells, 50 calibration cells and 841 references** across
the ten previously declared development plots. All detector and calibration
cells remain planned. No model was run, calibrator fitted or ranking produced.
The three reserve plots and six historical-test plots remain unchanged; their
point records were not parsed for this declaration.

This follows the [input validation](fgiemit-development-input-results.md).
Installed candidate checkpoint identity is verified, but upstream training
overlap remains unknown. The declared claim is therefore a conditional
development comparison, with no independent held-out claim or reserve release.

## Frozen Methods and Targets

| Component | Declaration |
| --- | --- |
| Detector cells | CHM-VWF, SegmentAnyTree and ForestFormer3D on all ten native-density development plots: 30 planned cells |
| Instance track | Two instance arms, 20 planned cells, unchanged reference masks and point-set IoU 0.5 matching |
| Detection track | All three arms, 30 planned cells, maximum pointwise AGL apexes and the existing FGI 4 m XY / 5 m absolute-Z matcher |
| Paired height diagnostics | Historical raw-Z maximum and isolated-top AGL, applied symmetrically to reference and predicted instances |
| Calibration | Ten whole-plot folds, three detection targets plus two separate mask targets: 50 planned validation cells |
| Pilot order | Plots 1001, 1019 and 1027; CHM-VWF, SegmentAnyTree, then ForestFormer3D per plot; one cell at a time, 3,600-second limit |

The measured original first-return densities select a 0.25 m CHM and no
smoothing on all ten plots. The variable window remains
`min(max(0.10 * h + 3, 3), 5)` metres, with a 2 m minimum detection height.
The instance arms use fixed installed checkpoints and the same raw local-XYZ
support, with no reference labels or heights in model inputs. Both use the
same 40-point / 1.5 m raw-Z-extent instance filter for both scoring tracks.

Calibration uses arm-specific confidence features and separate detection/mask
outcomes. Equal scores are aggregated before weighted isotonic regression;
validation scores outside the training range remain unavailable. No threshold
search, fusion or cross-arm comparison of raw confidence scores is included.
These rules are frozen; fitting and validation metrics are future work.

## Reference Export

The new source-row reducer selects complete XYZ rows, with the lowest original
row ID breaking height ties. It serves reference and prediction instances
identically. It exports three profiles for every reference, giving **2,523
rows** in `reference_apexes.csv`. Original masks, A–D categories, boundary and
dead-tree references remain unchanged; no height threshold removes references.
The category counts are A: 307, B: 177, C: 249 and D: 108.

| Plot | References | AGL maximum selects a different row from raw maximum | Isolated-top AGL changes the maximum |
| --- | ---: | ---: | ---: |
| 1001 | 133 | 89 | 1 |
| 1005 | 87 | 50 | 0 |
| 1009 | 103 | 70 | 2 |
| 1013 | 28 | 25 | 0 |
| 1019 | 8 | 7 | 0 |
| 1020 | 62 | 27 | 1 |
| 1022 | 213 | 89 | 3 |
| 1024 | 62 | 38 | 1 |
| 1027 | 96 | 57 | 0 |
| 1031 | 49 | 33 | 2 |
| Total | 841 | 485 | 10 |

These are reference-row differences, not detection errors or performance
changes. Pointwise terrain subtraction can change which row is highest.
Only ten instances have an AGL top gap strictly above 0.25 m. The largest is
tree 5 in plot 1031: its default height is 10.628937 m and its diagnostic
height is 6.741491 m, a 3.887446 m gap. The diagnostic also moves XY to the
selected second-highest AGL row. Both profiles remain archived; neither is
selected by downstream scores.

The publisher's raw-Z outlier and local-ground procedure differs from this
AGL diagnostic, as described in the protocol. Published heights are not used
as matching references or model inputs. Geometric normalization permits a
consistent comparison but still lacks independent AGL validation. Height
diagnostics cannot change the primary instance-mask target.

## Runtime Evidence and Remaining Execution Checks

The declaration records installed lasR 0.21.0, lidR 4.3.2, terra 1.8.29,
sf 1.0.19 and data.table 1.18.4. The installed lasR accepts the required
variable-window function. Its package metadata contains neither a remote
branch nor source commit, so the receipt records build lineage as unverified
and hashes its installed description, R databases and shared library. Version
number alone does not identify this build. Before CHM execution, the runner
must establish the documented `r-lidar/lasR@pre-devel` lineage.

A development runner still needs validated per-plot local frames, exact
source-row correspondence and resource measurements. In particular, historical
SegmentAnyTree nearest-neighbor transfer is insufficient: all retained rows,
including background and duplicate XYZ rows, must have an unambiguous label.
The fixed matrix records execution as disabled until these checks pass.
No runtime or model-memory feasibility claim follows from this declaration.

The next implementation is the bounded development pilot runner under this
contract. Failed cells must retain their failure status; they cannot become
zero detections, trigger automatic parameter rescue or silently disappear from
the denominator. Full-population comparisons pool counts before calculating
rates and use paired whole-plot bootstrap intervals. Reserve evaluation stays
closed pending a separate frozen development policy and overlap decision.

## Reproduction and Verification

Use the existing Python and R environments and installed Docker images. The
checkpoint audit uses read-only, network-disabled containers with no GPU or
host-data mounts. Run from the comparison checkout:

```sh
PYTHON=/path/to/lidar_tree_benchmarks/gpu/.venv/bin/python
ROOT=/path/to/work/external/fgiemit
OUT="$ROOT/development_comparison"
"$PYTHON" scripts/declare_fgiemit_comparison.py --root "$ROOT" --out "$OUT"
"$PYTHON" scripts/declare_fgiemit_comparison.py --root "$ROOT" --out "$OUT" --verify
```

Creation requires a new immediate output directory under the data root.
It verifies the original development declaration, prepared inputs and installed
checkpoint receipt before reading development references. Replay checks the
same parents, code, runtime identities and all new output hashes.

The receipt records 181 protected prior artifacts, four explicit parent
receipts and twelve candidate code/protocol files. Existing preparation/source
verification remains in force. Three outputs are sealed alongside the new
declaration receipt:

| Output | SHA-256 |
| --- | --- |
| `matrix.json` | `4907e0399d17e55fb4cb354b03d28e22fb014abe205f93e6ab1c8d890d305997` |
| `cells.csv` | `e82fd2590a99ba5ac353eb2c055cffacf38ee2194ab83813ce5057516c99b838` |
| `reference_apexes.csv` | `ab96a897b6b216f76c5b65e96749d7410848b383cfe5fe2cb635344bc99d93e6` |

- Real-data construction and independent replay passed for all ten plots.
- Full Python discovery: 38 tests, 36 passed; optional TreeAIBox and
  ForestFormer3D checkout tests skipped in the isolated worktree. New tests
  cover height ties, the strict outlier boundary, row identity, original R
  matching behavior, matrix/fold guards and rejection of changed receipts.
- Full R suite passed, with existing skips for the gated legacy-cylinder GPU
  smoke, unsupported empty-LAS fixture and default Python's missing `plyfile`.
  The R package-index network warning remains.
- README summaries, commands, requirements and indexes are updated.
  Repository-wide Markdown lint and whitespace checks pass before publication.

The real-data check validates reference construction and provenance only.
No detector smoke test or calibration fit belongs to this completed stage.
