# FGI-EMIT Development Metadata Audit

Completed on 2026-09-23 using the
[declared metadata selection rule](../docs/fgiemit-development-protocol.md).
The audit reserves three previously unprocessed training plots for prospective
evaluation and defines ten development folds. It runs no detector, inspects no
score values and fits no calibration. All real-data admission flags remain
false pending the support, frame and provenance checks below.

## Inputs and Audit Boundary

The existing [FGI-EMIT release](https://doi.org/10.5281/zenodo.19351234) contains
13 training plots and six test plots. This audit verifies the pinned metadata
and training-archive MD5s, then compares every extracted training LAS with its
archive member using SHA-256. All 13 match. It parses their headers, including
original return counts, but no point records or per-point labels. Published
tree counts and crown-category metadata are used as descriptive inventory.

The archived workspace contains training-processing evidence only for 1001
and 1019, matching the earlier adapter audits. No such evidence was found for
the other 11 training plots. This check inventories artifact names below the
FGI-EMIT working root, excluding source data, model checkouts and this audit's
output. It cannot establish absence of runs elsewhere or upstream checkpoint
training overlap. Existing source inputs and 128 archived metadata, score and
receipt files have matching hashes before and after the audit; score values
were not parsed.

The publisher's six test plots remain the observed historical baseline. Their
point files are not opened by this audit, and their results are not recomputed.

## Declared Split

The selection rule sorts the 11 remaining training plots by published tree
density, splits them into groups of four, four and three, and reserves the
lower median of each group. It uses neither detector scores nor LiDAR return
density. The two previous audit plots are always development plots.

| Role | Plots | Trees | A | B | C | D |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Development | 1001, 1005, 1009, 1013, 1019, 1020, 1022, 1024, 1027, 1031 | 841 | 307 | 177 | 249 | 108 |
| Prospective evaluation reserve | 1003, 1010, 1023 | 257 | 100 | 58 | 74 | 25 |
| Historical test, excluded from the new split | 1002, 1004, 1008, 1012, 1018, 1028 | 463 | 204 | 73 | 128 | 58 |

Development uses ten leave-one-whole-plot-out folds. Each has one validation
plot and nine calibration plots. Reserve and historical-test IDs never enter
those folds. This is a within-dataset reserve carved from the publisher's
training split, not a new external-site holdout. Published annotation counts
are known; reserve predictions and evaluation remain unobserved here.

| Metadata stratum | Candidate order, from lower to higher trees/ha | Reserved plot | Reserve trees | Reserve D trees |
| --- | --- | --- | ---: | ---: |
| Lower | 1013, 1023, 1020, 1031 | 1023 | 48 | 2 |
| Middle | 1024, 1003, 1005, 1027 | 1003 | 54 | 4 |
| Upper | 1009, 1010, 1022 | 1010 | 155 | 19 |

Category D remains concentrated: plot 1010 has 19 of the reserve's 25 D trees,
and development plot 1022 has 55 of its 108. Report plot-level counts and
uncertainty; these totals do not establish broad understory generalization.

## Source Headers and Remaining Gates

All training files use LAS point format 7, expose `tree_index`, retain multiple
return numbers and have no declared CRS. Their local Z minima are zero; that
does not establish height above ground. Header return counts sum to the point
count in every file.

| Reserved plot | Source points | First-return points | Published area, ha | Estimated all-return points/m² | Estimated first-return points/m² |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1003 | 2,308,748 | 1,677,881 | 0.126 | 1,832.340 | 1,331.652 |
| 1010 | 3,622,071 | 2,947,005 | 0.196 | 1,847.995 | 1,503.574 |
| 1023 | 5,510,572 | 4,356,067 | 0.283 | 1,947.199 | 1,539.246 |

These estimates divide header counts by rounded published areas and include
points that later support rules may exclude. They are not approved detector
density inputs. Across all training plots, these first-return estimates range
from 1,019 to 1,721 points/m² and all-return estimates from 1,244 to 2,454.
The initial declaration therefore covers native density only; no sparse-rung,
optical-fusion or general density-routing claim is supported.

Before a real comparison:

- Preserve the plot-local metric frame and explicit source identity. Do not
  invent an EPSG code or equate separate plots' local coordinates.
- Verify reference IDs, boundary/background rules and common scoring support
  from the original records. Header presence of `tree_index` is insufficient.
- Measure both densities on retained source support before the geometry bridge.
  The historical `fgi_model_points()` overwrites return metadata with ones;
  first-return density measured from its prepared files would be misleading.
- Verify normalization and AGL heights. A zero local minimum is not ground.
- Resolve checkpoint overlap and seal the intended comparison matrix and fresh
  calibration definitions. The metadata split alone supplies neither.
- Establish resource limits using development inputs. Reserve plot 1023 has
  5.51 million source rows, exceeding the 3.76 million source rows of the larger
  previous training-audit plot; prepared supports will need their own counts.

No detector settings were changed to accommodate these findings. The reserve
must not be replaced in response to future failures or inconvenient scores.
The [protocol](../docs/fgiemit-development-protocol.md) defines the admission
gates; the next implementation is development-input preparation and validation.

## Reproduction and Artifacts

Use the existing Python environment with `laspy` and `PyYAML`. No model runtime
or new package installation is needed. An isolated checkout needs an explicit
path to that environment and the existing data root:

```sh
PYTHON=/path/to/lidar_tree_benchmarks/gpu/.venv/bin/python
ROOT=/path/to/work/external/fgiemit
OUT="$ROOT/development_declaration"
"$PYTHON" scripts/audit_fgiemit_development.py --root "$ROOT" --out "$OUT"
"$PYTHON" scripts/audit_fgiemit_development.py --root "$ROOT" --out "$OUT" --verify
```

`OUT` must be a new immediate child of `ROOT`. Verification checks source and
protected receipts, code/protocol identity, reserve-processing evidence and
generated output hashes. A changed source, protocol, receipt or prior reserve
attempt fails; existing outputs are never overwritten or silently relabelled.

| Artifact | Contents |
| --- | --- |
| `plot_inventory.csv` | All 19 published plots, roles, counts, folds, prior processing evidence and training-header estimates. |
| `folds.json` | Ten explicit validation/calibration plot sets. |
| `declaration.json` | Release pins, 15 source-file hashes, 128 protected receipt hashes, source-header metadata, code/protocol identity and false admission flags. |

The Python suite passes with two optional upstream-checkout skips. The audit
and verification run on the real local release pass. Repository-wide Markdown
lint and whitespace checks pass. R code and GPU adapters are unchanged; no R
suite or GPU inference was run for this Python metadata-only change.
