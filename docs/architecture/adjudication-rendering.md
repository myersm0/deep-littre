# Adjudication application and rendering

Resolution consumes explicit XMLittré facts plus applicable adjudication records and produces one semantic representation shared by TEI and SQLite.

## Store layout

```text
data/adjudication/
  sublemma/
    a.jsonl
  voice_variant/
    d.jsonl
  qualification_scope/
    a.jsonl
```

JSONL is canonical and deterministic. There is no store manifest.

## Applying a record

An `ExaminationRecord` is first matched to the current census. Its raw block span is a fast locator, while `surface_sha256` decides whether the old judgment still describes the current classification surface.

When valid, projected selections are translated through the current projection and source transform into runtime raw spans. Downstream resolver code receives `AppliedRecord`/anchored assertions and does not need to know how the durable record survived coordinate drift.

A missing old locator may be recovered only by a unique same-file surface-hash match. A changed block at the old locator is stale without fallback.

Ordinary builds report stale records and skip them. Strict release builds reject them. Malformed or internally inconsistent records are store-integrity errors in both modes.

## Structural closure

An ordinary `Sense` is derived only when every structural alternative has examined the block with an applicable, non-unresolved verdict and there is no structural conflict. Complete positive partitions were already verified when records were authored and are revalidated when persisted records are materialized.

Positive `SubLemma` and `VoiceVariant` assertions become explicit child nodes. Their geometric containment determines parentage; parent ids are not persisted.

## Qualification scope

Explicit `<semantique>` and `<nature>` facts are always reconstructed deterministically. Containment is their default scope. An applicable scope assertion may move the marker to its adjudicated target but does not change the marker normalization.

## Coverage

Coverage is computed from the current code-defined population and applicable records. Each pass reports population size/hash, examined/positive/negative/unresolved counts, and the number of stale records.
