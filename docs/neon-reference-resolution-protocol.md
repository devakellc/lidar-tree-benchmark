# NEON Reference-Resolution Protocol

**Archived after the 2026-09-18 [HARV/BART closeout](harv-bart-closeout.md).**
The declarations below document the retired study, not authorization to resume
it. Existing safeguards and diagnostic-only status remain unchanged.

This follow-up explains flagged records without changing the earlier
[bole-level support](neon-reference-support-protocol.md). It is not an
evaluation-admission declaration. Preserve all original records, support
identities, exclusions and historical detector outputs.

## Record Resolution

Join evidence using exact plot, census event and individual identity. Interpret
per-bole versus per-individual measurements using the event's field protocol
and the released variables table, not the apparent completeness of a row.

For `multi-bole tree` records only, the documented trailing letter links an
additional bole to the unsuffixed individual. Require the standard permanent
identifier format and a unique same-event primary record. Do not strip arbitrary
suffixes, join across plots/events, or use `supportingStemIndividualID`: that
field describes the tree supporting a liana, not a multi-bole relationship.

Retain related records below the original 10 cm threshold and dead/broken
boles as evidence. These records can explain where individual-level height
was recorded; their presence does not change the declared scored population.
Expose missing, ambiguous, quality-flagged or inconsistent family links.

Classify additional-bole records separately from primary broken boles and
unknown positional uncertainty. Export every observed failure, not only the
first exclusion reason. Record candidate height-bearing relatives without
copying their measurements or coordinates into another bole. `breakHeight`
describes a broken bole, not necessarily the highest living part of a tree.

Quantify subplot discrepancies against the existing surveyed geometry and
uncertainty margin. Do not move stems, enlarge boundaries, select old mapping
records or switch azimuth conventions to remove discrepancies. Small residuals
still need an explicit decision; they are not automatically field errors.

An eventual individual-level reference population requires a new declared
policy, unique tree-level denominators, location/height provenance and paired
regression checks. Explaining a missing per-bole value does not recover that
bole's independent apex or admit the existing bole-level support.

## Spatial Provenance

Archive official field, datum and product documentation, flight dates and the
HARV flightline-boundary/trajectory reports. Bounded 64 KiB flightline header
excerpts link tile Point Source IDs to published File Source IDs; zero or
ambiguous IDs do not establish attribution. Download only the already selected
HARV_033 LiDAR tile for the bounded time/point-source inspection. Do not acquire
BART imagery or point clouds and do not run detectors or fit alignment offsets.

Keep flightline-footprint intersection, GPS-time consistency and demonstrated
point contribution as different evidence levels. GPS week time lacks a week
number; a published flight schedule may narrow candidates but is not a hidden
timestamp. For the 2022 inspection use the declared GPS-minus-UTC offset of
18 seconds, retaining both calendar-day candidates near midnight. Do not
derive acquisition dates from file creation or publication.
Retain unresolved or ambiguous line/time associations explicitly.
KML lines are noded into conservative candidate enclosures. Interior holes
may be filled for this candidate search; these are not verified coverage masks.

Distinguish a documented AOP datum convention from field-marker realization,
survey epoch and positional accuracy. Do not apply a historical vertical shift
to current data merely because a technical report describes one. Above-ground
tree heights are not field-marker elevations or absolute LiDAR elevations.

## Outputs and Stop Rule

Write record/family evidence, plot decisions, source hashes and remaining
upstream questions to a separate output root. Verify input and output hashes
on replay. Existing support stays diagnostic-only throughout this follow-up.
Once released records and the directly relevant official sources have been
checked, record unresolved questions instead of repeatedly downloading data or
relaxing safeguards. No split freeze, calibration or detector scoring follows
automatically from an explained exclusion.
