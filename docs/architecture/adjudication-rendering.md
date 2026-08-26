# Adjudication store and renderer contracts

Status: **normative v0.3 data-flow specification**.

## Data flow

Hand, LLM, and deterministic adjudications are committed **inputs**. TEI and SQLite are generated outputs.

```text
XMLittré + patches
        ↓
source representation + SourceBlock census
        ↓                              ↓
explicit markup                 authoritative
    ↓ deterministic             adjudication store
normalized facts                       ↓
        ↘                            ↙
        resolved semantic representation
                   ↙ ↘
            TEI Lex-0   SQLite
```

Resolve consumes two qualitatively different inputs and does not conflate them. Facts XMLittré
states explicitly — `<semantique type="indicateur">Fig.</semantique>`, `<nature>loc. adv.</nature>`,
author attribution, etymology segmentation — are reconstructed every build from source, code, and
the committed normalization tables. They are not durable judgments and do not occupy the store.
The store holds examinations whose positive/negative/unresolved state and provenance must survive:
structural decomposition, qualifications inferred from prose rather than markup, and ambiguous
scope.

The resulting test boundary: deleting the adjudication store entirely must still produce a coarse
corpus containing every safely recoverable explicit XMLittré fact, and adding adjudications must
enrich structure monotonically rather than recreate facts that were already present.

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

The manifest records the versions in force when the store was written. It is read to interpret older records and to migrate them; it is documentation and a migration input rather than a gate. Store-wide gates are deliberately few, because a store-wide gate converts a local question into a global one: a manifest that named the corpus by hash failed the entire store, before any record was read, when one byte changed in a letter holding no records at all.

Everything a record asserts about itself — pass, population, projection, their versions, the raw anchor, the projected view, target eligibility — is checked per record, where a mismatch quarantines one verdict. What remains store-wide has no per-record equivalent: the structural alternative-set and closure-protocol versions, which govern the resolver's closure derivation rather than any individual verdict; a nonempty store with no manifest at all; and records for a pass the code does not run, which would otherwise be read by nobody and pass silently.

The authoring harness is the only supported writer of durable adjudication records. Humans, LLMs, and rule implementations return semantic decisions to the harness; they do not author byte offsets, hashes, record ids, or serialized JSON directly. See `adjudication-authoring.md`.

### Canonical JSONL

Committed JSONL is deterministic:

- UTF-8, no BOM, LF line endings;
- exactly one compact JSON object per line;
- stable schema-defined key order, including nested objects;
- records sorted by `(source.file, source.start_byte, source.end_byte, pass, record_id)`;
- arrays retain semantic order where order matters;
- regeneration with identical inputs is byte-identical.

Historical tagged/labeled TSV/CSV assets are not presumed to be adjudicated records or evaluation ground truth. Their provenance is reviewed first; they may remain audit/reference data, become evaluation data, or be imported later through the authoring harness if their status is established.

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
context             optional 0..N ContextReference objects
outcome            positive | negative | unresolved
exhaustive         Bool
assertions         0..N typed assertions
scopes             0..N scope assertions
residuals          0..N raw spans
decision_procedure String, opaque
decision_reference optional String, opaque
created            ISO date/time
notes              String
```

**How a verdict was reached is not the pipeline's concern.** The store consumes verdicts and knows
nothing about how they were produced: there is no method vocabulary, no model identifier, and no
prompt or model-input hash in the record. `decision_procedure` names the external process that
produced the verdict and `decision_reference` is an opaque pointer into that process's own records.
Neither is interpreted here. Prompt versioning, question sets, model identity, response evidence,
and any deterministic combiner that turns evidence into a verdict are tracked by that process,
outside this repository.

The store therefore holds **current verdicts, not their history**. At most one record may exist per
target per pass; a second is a store integrity failure rather than a revision, because no honest
precedence rule could choose between them. Superseding a verdict means regenerating the pass.

`negative` means the pass examined the eligible material and found that its semantic class does not apply. It is not represented by absence. Negative outcomes may be established by a deterministic rule pass and are first-class adjudications; they do not imply individual human deliberation. A rule may emit a negative only when its logic is entitled to establish absence for that class over the declared population. Mere failure of a heuristic detector is not evidence of a negative.

`unresolved` means the pass examined the material but declined to make a positive or negative claim.

Absence of a record means the pass has not examined that eligible material.

A record fails closed if either the raw-anchor check or adjudicated target-view check fails.

Context records what the adjudicator was shown alongside the target. It is provenance, not a second validity channel:

```text
source.file        String
source.start_byte  Int
source.end_byte    Int
role               optional String
```

Every context reference must lie inside the record's own raw span, which is checked at commit and again at application. Given that containment, the record's `raw_sha256` already covers the context bytes, and a change to them fails the record as a raw-anchor mismatch. Giving each context item its own raw and view hash duplicated that check.

Context drawn from *outside* the target span — a neighbouring entry or sense — would not be covered and would need its own check. No pass draws context that way today, and one that did would be introducing the requirement along with the pass.

## Rule-established negatives

Per-target records are the right shape for individually reached verdicts, unresolved cases, and
exceptions. Whether they remain the right shape for a deterministic rule establishing the same
outcome over a versioned population is an open question: materializing per-block structural
negatives plus closure across the corpus would commit on the order of 10⁶ records dominated by
hash fields.

A compressed representation — one assertion naming a rule, a population, and an outcome, expanded
to per-target state at resolution — was specified and implemented ahead of any rule pass that would
produce one, and was removed unused. It should be reintroduced against a real rule pass, whose
actual shape will determine what the assertion has to carry, rather than designed against a
hypothetical one.

`segmentation_complete` is **resolver-derived rather than stored**. Given exhaustive-pass status,
residual geometry, applicable negatives, and the absence of unresolved or conflict records, closure
is a deterministic predicate. At most one record per target per pass is applicable, so there is
nothing for the resolver to choose between: the store holds current verdicts, and two records for
one target are rejected rather than ordered. A closure record is committed only if empirical work
reveals an independent segmentation judgment that cannot be derived.

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

`SubLemma` and `VoiceVariant` are form-bearing. `Sense` is not. A form-bearing node serializes
entry-like: `SubLemma` as `<entry type="relatedEntry">`, `VoiceVariant` as
`<entry type="homonymicEntry">`, both verified against the pinned RNG. See
`semantic-model.md` for the `VoiceVariant` definition and its boundary against grammatical
construction facts.

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
{SubLemma, VoiceVariant}
```

Closure protocol version 1 additionally requires `segmentation_complete`. It is a block/span closure record, not a semantic class or member of the alternative set. It asserts that the current structural passes have produced a complete ordered partition of the eligible material into positive node spans and explicit residual spans, with no unresolved structural boundary remaining.

That partition is **verified, not trusted**. The resolver projects the target and requires every
source-visible character to be claimed by a node span or a residual span. An exhaustive claim over
material the adjudicator did not account for yields no derived sense and an `incomplete_partition`
review finding naming the unaccounted text. Absence of a record is different: a block nobody has
examined is the ordinary intermediate state and is not a review finding.

A persisted examination target is a census `SourceBlock`. Residual spans are closure regions rather than independently addressable targets, and no per-residual records are written. A positive structural examination contains several node assertions plus the explicit residual spans that demonstrate its exhaustion; those residuals are evidence for the partition check, not targets of their own.

This costs nothing under alternative-set version 1, because a block-level result already determines every residual within the block. A negative result establishes its alternative as absent throughout the block. A positive exhaustive result establishes it on the asserted node spans and absent everywhere else in the block. The corresponding per-residual negatives are derived, never stored.

For a block's direct content to derive as an ordinary `Sense`:

- `SubLemma` is negative on the block, or positive and exhaustive with the direct content outside its assertions;
- `VoiceVariant` likewise;
- `segmentation_complete` is true under closure protocol version 1;
- the block was eligible for every alternative pass;
- all records were evaluated against structural alternative-set version 1.

The derived `Sense` node's span is the enclosing block, not its direct content. After carving, the direct content is discontinuous, and a parent extent containing its descendants is the ordinary reading of a source-anchored tree.

If any condition is absent or unresolved, the semantic type remains underdetermined. The renderer may still serialize the material coarsely without claiming that a completed adjudication established an ordinary sense.

## Coverage

`manifest.toml` defines each pass population by name and version, records the structural alternative-set and projection versions in force, and identifies the exact raw source corpus. The store manifest is validated before coverage or resolution reads any pass records.

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

The `SourceBlock` census is the denominator of record; each pass's eligible population is an explicit subset. A population hash is computed from the ordered durable source anchors so a changed denominator cannot masquerade behind the same count.
Coverage counts the current logical decision for each eligible target, not every historical examination record retained in the audit trail. Historical revisions remain store history but do not inflate `examined`, `positive`, `negative`, or `unresolved`.

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

This stage is the only place that derives ordinary `Sense`, resolves parentage, and verifies target references. Parentage is geometric: among containing structural nodes, the smallest strict containing span is the parent. Descendant source blocks skipped from an enclosing adjudication projection are likewise nested under an asserted node when its raw span contains them. Coincident or crossing structural assertions remain review conflicts and are withheld from the resolved semantic tree.

## TEI renderer contract

The TEI renderer is a pure serialization of resolved facts plus mechanical XML escaping/formatting. It emits structural indentation and line breaks so the corpus is inspectable by a human. Mixed-content payloads are serialized compactly inside their owning element; formatting never inserts whitespace inside a definition, quotation, segment, orthographic form, pronunciation, emphasis, or reference payload.

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
- inline content segments;
- qualifications and their targets;
- relations;
- citations;
- rubriques;
- locution/sub-lemma forms as node data rather than a special parallel ontology;
- examination/adjudication records;
- pass/population coverage;
- reviewable unresolved records;
- full-text search surfaces.

### Node extents and inline content

A semantic node's `file`/`start_byte`/`end_byte` is its **container extent**, not the bytes
contributing directly to its own text. A `Sense` containing a `SubLemma` spans the sub-lemma too;
containment is what the interval structure expresses, and exclusive ownership is not implied.

Direct content lives in `content_segments`, the ordered inline pieces of a node's definition, a
rubrique's prose, or a citation's quotation, each carrying its own raw span. This is where the
structure the resolver recovered stays queryable rather than being flattened into a string: a
cross-reference keeps its resolved target, a source wrapper keeps which element it was and what
language it declared. The flattened text column beside each owner is for reading and search.

Rubriques and citations are keyed by their raw anchor rather than by a minted identifier, so a
rebuild produces the same keys.

Any inline fact represented in TEI and absent from `content_segments` is a parity failure, not a
serialization difference.

Convenience views may reconstruct familiar user queries such as "figurative senses" or "all sub-lemmas", but they are derived from typed facts.

## Cross-output invariants

Tests assert semantic parity rather than matching XML and SQL implementation details.

At minimum:

- every rendered TEI semantic node has a corresponding SQLite semantic node;
- node types and containment agree;
- every TEI `<usg>`/`<gram>` fact has the same axis/norm/target in SQLite;
- every cross-reference relation is represented in both outputs, with the same resolved target;
- every inline source wrapper retained in TEI has a corresponding content segment;
- citation counts and resolved authors agree;
- source anchors and provenance remain queryable from SQLite;
- no renderer invents a fact absent from the resolved model.

Schema validation is an additional TEI gate, not a substitute for these semantic invariants.
