# Adjudication store and renderer contracts

Status: **normative v0.3 data-flow specification**.

## Data flow

Hand, LLM, and deterministic adjudications are committed **inputs**. TEI and SQLite are generated outputs.

```text
XMLittré + patches
          ↓
source representation + census
          ↓
authoritative adjudication store
          ↓
resolved semantic representation
         ↙ ↘
TEI Lex-0   SQLite
```

The generated database mirrors adjudication/provenance data for querying but is never the sole home of an expensive judgment.

## Store format

The authoritative store is text-based and diffable.

Use:

```text
data/adjudication/
    manifest.toml
    sublemma/
        a.jsonl
        b.jsonl
        ...
    voice_variant/
        a.jsonl
        ...
```

JSON Lines is used for examination/adjudication records because records contain typed target references and zero or more assertions; one record per line keeps diffs local and supports streaming over corpus-scale files. TOML is used for the small manifest of pass, population, projection, and alternative-set versions.

The authoring harness is the only supported writer of durable adjudication records. Humans, LLMs, and rule implementations return semantic decisions to the harness; they do not author byte offsets, hashes, record ids, or serialized JSON directly. See `adjudication-authoring.md`.

### Canonical JSONL

Committed JSONL is deterministic:

- UTF-8, no BOM, LF line endings;
- exactly one compact JSON object per line;
- stable schema-defined key order, including nested objects;
- records sorted by `(source.file, source.start_byte, source.end_byte, pass, record_id)`;
- arrays retain semantic order where order matters;
- regeneration with identical inputs is byte-identical.

Historical labeled TSV/CSV assets are not presumed to be records that must be migrated. They may instead remain evaluation sets or be imported later through the authoring harness once their role is decided.

## Examination record

The unit of coverage is one eligible source block or target span examined by one pass.

Each record contains at least:

```text
record_id          String, opaque and stable across re-anchoring
pass               String
pass_version       Int
population         String
population_version Int
source.file        String
source.start_byte  Int
source.end_byte    Int
source.raw_sha256  String
source.synthetic_boundary Bool
view.projection    String
view.version       Int
view.sha256        String
outcome            positive | negative | unresolved
assertions         0..N typed assertions
method             human | llm | rule
adjudicator         String
model               optional String
created             ISO date/time
release             optional String
resolution_metadata optional object
```

`negative` means the pass examined the eligible material and found that its semantic class does not apply. It is not represented by absence. Negative outcomes may be emitted in bulk by a deterministic rule pass and are first-class adjudications; they do not imply individual human deliberation. A rule may emit a negative only when its logic is entitled to establish absence for that class over the declared population. Mere failure of a heuristic detector is not evidence of a negative.

`unresolved` means the pass examined the material but declined to make a positive or negative claim.

Absence of a record means the pass has not examined that eligible material.

A record fails closed if either the raw-anchor check or adjudicated-view check fails.

## Semantic assertions

Assertions describe semantic facts, not source-container labels.

### Node assertion

A semantic node has:

```text
node_id      String, opaque and stable
node_type    Sense | SubLemma | VoiceVariant | ...
span         one contiguous raw SourceSpan
parent       optional node_id or structural parent target
constituents optional named sub-spans
```

A source block may yield zero, one, or many nodes. Semantic node spans must form a **laminar** interval structure: two node spans are either disjoint or one contains the other. Partial crossing overlap is invalid and produces a structural-conflict review item before rendering. One node's primary span is contiguous. Qualification marker spans and their targets are not subject to this node-laminarity rule and may overlap nodes as required.

`SubLemma` and `VoiceVariant` are form-bearing. `Sense` is not.

`form` and `gloss` are constituent sub-spans of a `SubLemma`, not separate node types. Their raw coordinates are resolved by the authoring harness from selections in the versioned adjudication projection; an LLM or human never computes raw offsets directly. Ambiguous or unmappable selections fail closed to review.

### Qualification assertion

A qualification has:

```text
qualification_id String
axis             one Lex-0 usage axis or grammatical family
norm             optional canonical value
printed          source-visible value
source_span      SourceSpan
target           TargetReference
```

Lex-0 usage axes are:

- `socioCultural`;
- `attitude`;
- `meaningType`;
- `domain`;
- `temporal`;
- `frequency`;
- `textType`;
- `normativity`;
- `geographic`;
- `hint`.

`register` is not an axis. A printed source label historically grouped as register is adjudicated/routed directly to the relevant Lex-0 axis or axes. Compound labels may create multiple qualifications.

The grammatical family is separate from `<usg>` and renders through `<gramGrp>/<gram>`.

### Relation assertion

Cross-references are relations rather than qualifications. A relation stores source span, relation type, source target, and lexical target text/reference. Renderer-specific `target="#xml-id"` is generated only when a reliable published target exists.

## Target references

A `TargetReference` is one of:

```text
SpanTarget
    raw span

NodeTarget
    node_id

SiblingRangeTarget
    parent node_id
    first node_id
    last node_id

RubriqueTarget
    source rubrique id / raw span
```

Scope is therefore explicit in the stored fact.

Transition-specific labels such as strong/medium/intra-sense/zero and citation veto are inference-resolution metadata, not the scope representation itself.

## Segmentation closure and ordinary `Sense`

No adjudication pass owns the assertion "the remainder is an ordinary sense" merely because its own class was absent.

v0.3 uses structural alternative-set version 1:

```text
SubLemma
VoiceVariant
segmentation completeness
```

`segmentation_complete` is a block/span closure record, not a semantic class. It asserts that the current structural passes have produced a complete ordered partition of the eligible material into positive node spans and residual spans, with no unresolved structural boundary remaining.

For a residual span to derive as an ordinary `Sense`:

- `SubLemma` is negative on that span;
- `VoiceVariant` is negative on that span;
- segmentation is complete;
- the span was eligible for every alternative pass;
- all records were evaluated against alternative-set version 1.

If any condition is absent or unresolved, the semantic type remains underdetermined. The renderer may still serialize the material coarsely without claiming that a completed adjudication established an ordinary sense.

## Coverage

`manifest.toml` defines each pass population by name and version and records the structural alternative-set and projection versions in force.

A release coverage record contains:

```text
pass
pass_version
population
population_version
population_size
population_hash
examined
positive
negative
unresolved
```

The universal source census is the denominator of record; each pass's eligible population is an explicit subset. A population hash is computed from the ordered durable source anchors so a changed denominator cannot masquerade behind the same count.

For version 1, any qualification pass whose source phenomenon can occur at `<variante>` level includes variantes in its eligible population. This applies in particular to usage-label families such as `domain`, `meaningType`, `socioCultural`, `attitude`, and the other Lex-0 qualification axes when their markers occur there. Structural passes may define narrower populations when justified.

## Resolved semantic representation

Renderers do not read JSONL files directly and do not perform semantic detection.

A resolution stage combines:

- source structure;
- semantic node assertions;
- qualifications;
- relations;
- coverage/exhaustion state;
- retained orthogonal enrichments such as author resolution and etymology events.

It produces one immutable resolved representation consumed by both renderers.

This stage is the only place that derives ordinary `Sense`, resolves parentage, and verifies target references.

## TEI renderer contract

The TEI renderer is a pure serialization of resolved facts plus mechanical XML escaping/formatting.

It must not:

- classify an indent from punctuation or lexical cues;
- decide whether prose is a sub-lemma;
- infer qualification scope;
- silently turn an unknown node/property into a generic sense;
- publish workflow state as semantic markup.

Partially adjudicated material is rendered coarsely but truthfully. A source block with no resolved finer structure may appear as a `<sense><def>…</def></sense>` without implying that an adjudicator positively established an ordinary `Sense`.

`ana="unclassified"` is not emitted in v0.3.

Detailed XML requirements live in `docs/tei-lex0-compliance.md`.

## SQLite renderer contract

SQLite is a queryable mirror of the same resolved semantic model and provenance, not an independent interpretation.

The v0.2 `senses.role`/`sense_type` vocabulary is not preserved as the internal ontology.

The v0.3 database should expose, directly or through views:

- entries;
- source blocks and raw spans;
- semantic nodes and containment;
- qualifications and their targets;
- relations;
- citations;
- rubriques;
- locution/sub-lemma forms as node data rather than a special parallel ontology;
- examination/adjudication records;
- pass/population coverage;
- reviewable unresolved records;
- full-text search surfaces.

Convenience views may reconstruct familiar user queries such as "figurative senses" or "all sub-lemmas", but they are derived from typed facts.

## Cross-output invariants

Tests assert semantic parity rather than matching XML and SQL implementation details.

At minimum:

- every rendered TEI semantic node has a corresponding SQLite semantic node;
- node types and containment agree;
- every TEI `<usg>`/`<gram>` fact has the same axis/norm/target in SQLite;
- every cross-reference relation is represented in both outputs;
- citation counts and resolved authors agree;
- source anchors and provenance remain queryable from SQLite;
- no renderer invents a fact absent from the resolved model.

Schema validation is an additional TEI gate, not a substitute for these semantic invariants.
