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
  bare_qualification/
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

Explicit `<semantique>` and `<nature>` facts are always reconstructed deterministically. Containment is their default scope. An applicable `qualification_scope` assertion may move an explicit marker to its adjudicated target but does not change its normalization.

A `bare_qualification` assertion first establishes that an exact prose span is a qualification marker and records what it governs. Resolution then removes those marker bytes from the coarse definition and routes the printed marker text through the same committed normalization tables. The durable record does not store the normalized semantic value.

## Coverage

Coverage is computed from the current code-defined population and applicable records. Each pass reports population size/hash, examined/positive/negative/unresolved counts, and the number of stale records.
## Renderer contracts

Both renderers consume only the resolved representation. They may serialize, escape, format, and mint output-local identifiers; they may not classify source material, infer a qualification or relation, repair an unresolved structural judgment, or publish workflow state as semantic markup.

### Node extents and inline content

A resolved node's raw span is a container extent, not exclusive ownership of every byte it covers. A parent may therefore span nested structural children. Direct textual content is carried separately as ordered inline segments; punctuation between form/gloss constituents is carried explicitly as a separator rather than silently attached to either constituent.

This distinction is load-bearing across both outputs: containment comes from node extents, while textual ownership and inline structure come from the resolved content representation.

### TEI renderer contract

The TEI renderer:

- serializes the node hierarchy already present in `Resolve`;
- serializes `SubLemma` as nested `entry type="relatedEntry"` and form-bearing `VoiceVariant` as the corresponding entry-like variant representation;
- serializes the first resolved form as `form type="lemma"` and additional forms as `form type="variant"`; a form carrying an editorial value uses condensed `<orth value="…"/>` rather than fabricated printed text;
- emits resolved qualifications, grammatical facts, relations, rubriques, and citations on their resolved targets;
- may introduce wrapper structure required by Lex-0, but must not turn an underdetermined workflow state into a semantic assertion;
- emits no `ana="unclassified"` workflow marker;
- must pass the pinned Lex-0 schema gate.

Generated `xml:id` values are rendering identifiers only. They are not adjudication identity and need not remain stable when resolved structure changes.

### SQLite renderer contract

SQLite is a queryable mirror of the same resolved facts, not an independent interpretation. In particular:

- `node_type` remains null where semantic type is underdetermined;
- node raw spans are container extents;
- ordered `content_segments` preserve direct inline content and its structure rather than flattening it away; spans inherited from XMLittré `<exemple>` carry `editorial_origin = 'gannaz'`, while other source wrappers leave that field null;
- constituent spans, qualifications, relations, rubriques, citations, provenance, review findings, and coverage remain queryable;
- output-local keys may use current raw anchors where appropriate, but those keys are not durable adjudication identity.

### Cross-output invariants

TEI and SQLite must agree on semantic content even though their serialization structures differ. Tests therefore require parity for:

- resolved node types and containment;
- qualification/grammatical axis, norm, and target;
- cross-reference relations and resolved targets;
- citation counts and resolved authors;
- structural constituent content;
- absence of semantic facts invented by either renderer.

Schema validity is an additional TEI requirement, not a substitute for semantic parity.
