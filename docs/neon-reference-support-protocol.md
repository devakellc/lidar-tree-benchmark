# NEON Reference-Support Protocol

This is a score-blind reference audit, not a detector comparison. Preserve all
historical inputs and rectangular scores. HARV remains development; BART is
held out. Do not freeze eligibility or run inference from these diagnostics.

## Population and Events

The initial target is live `single bole tree` and `multi-bole tree` records
with measured stem diameter at least 10 cm, finite positive height and mapped
coordinates. This is a mapped-bole detection reference, not an exhaustive
inventory of all crowns, saplings or small trees. Multi-bole identities are
retained; they are not silently combined into one crown.

Select exact-year measurements, joining census metadata on both `plotID` and
`eventID`. Preserve subplot, protocol, collection scope, quality flags and
measurement/mapping dates. Reject ambiguous census or individual records and
dendrometer-only events. Use the latest mapping record as recommended by the
[vegetation structure guide](https://data.neonscience.org/api/v0/documents/NEON_vegStructure_userGuide_vE.1),
retaining its date; tied conflicting mappings remain unresolved. Do not
substitute a nearest-year measurement or turn missing mappings into absences.

Smaller growth forms and nested subplots are explicitly outside this target.
Unknown or unsupported subplot encodings fail closed, not as a full plot.
A future nested-population analysis needs its own footprint and denominator.

## Geometry and Boundaries

Use the guide's Figure 2 point numbering: 100 m2 subplot corners are the
southwest anchor plus offsets 0, 1, 10, 9; 400 m2 corners use 0, 2, 20, 18.
Fetch all four named-point coordinates, preserve their API records and use
their measured quadrilateral. Never synthesize missing corners from a plot
centroid, a tower label or an area total. Four 100 m2 subplots also support
20 m tower plots; the historical tower-size default is not used for geometry.

The listed subplot areas must sum to the event's sampled tree area. Reject
duplicates, overlaps, invalid geometries and missing coordinate uncertainty.
Report measured polygon area separately from the nominal sampled area.

For an explicitly labelled conservative interior diagnostic, erode the union
by the largest recorded anchor/mapped-reference uncertainty plus 0.6 m for
rangefinder error. Retain the un-eroded measured footprint as a separate
export. Report excluded boundary references and the lost area. This margin is
a declared sensitivity policy, not a guaranteed confidence interval; unknown
uncertainty or an empty interior prevents evaluation.

## Scoring Contract

An opt-in polygon scorer filters references to the declared population and
interior. It retains the existing one-to-one matching and height gate, with
detections allowed within the matching tolerance around the interior for
recall. Precision counts only detections inside the interior. Unsampled
quadrants are never precision denominators. Even inside sampled polygons,
unmatched detections can represent trees outside the target population;
reference-relative precision is not independently verified tree precision.

Record geometry, event, population, uncertainty policy, input hashes and code
identity with outputs. Reject stale support caches and mixed-support pooling.
Synthetic fixtures compare the optional polygon path with the unchanged
rectangle path; this stage does not regrade actual detector outputs.

## Remaining Admission Checks

Prepared support bundles are diagnostic, not evaluation-ready. Missing target
references, quality flags, unsupported subplots and positional uncertainty must
be reviewed. Matching WGS84 EPSG headers alone do not reconcile NEON's ITRF00
product specification or establish field/AOP positional accuracy. Preserve
unresolved datum/flight provenance explicitly, including GPS-time conventions;
file-creation dates cannot establish acquisition dates.

Only after these checks and the remaining physical coverage/density preflight
may a separate reviewed declaration admit support for calibration or scoring.
No automatic override or score-selected footprint adjustment is provided here.
