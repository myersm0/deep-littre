# Adjudication authoring harness

Status: **normative v0.3 authoring specification**.

## Purpose

The authoring harness is the controlled boundary between an adjudicator and the authoritative adjudication store.

An adjudicator may be a human, an LLM, or a deterministic rule. The adjudicator decides semantic questions. The harness owns source identity, projections, source-coordinate translation, hashes, record ids, validation, canonical serialization, and review escalation.

No human or LLM is asked to author `start_byte`, `end_byte`, raw hashes, view hashes, projection versions, or JSONL records directly.

```text
source representation + census
        ↓
eligible item selected by pass
        ↓
versioned adjudication projection + provenance map
        ↓
human / LLM / rule decision
        ↓
harness validation + span resolution
        ↓
complete anchored adjudication record
        ↓
authoritative store
```

This component is on the critical path for corpus adjudication. A record format without a producer is not an implemented adjudication system.

## Responsibilities

The harness:

- enumerates the eligible population declared by an adjudication pass;
- selects the source block/span and any surrounding context allowed by that pass;
- renders the versioned adjudication projection;
- retains a provenance map from projected text back to source intervals;
- assigns an ephemeral item id for the interaction;
- invokes or presents the pass-specific adjudication protocol;
- validates the returned decision against the pass schema;
- resolves projected selections to durable raw source spans;
- computes raw and projected-view hashes;
- assigns stable opaque record/assertion ids;
- records method/model/prompt provenance;
- emits canonical JSONL through the authoritative-store writer;
- fails closed to a review queue when a decision cannot be mapped or validated unambiguously.

The harness does **not** infer semantic answers that the selected adjudication method did not establish.

## Adjudication passes

An adjudication pass is a versioned question over a versioned eligible population.

A pass definition states at least:

```text
pass
pass_version
population
population_version
projection
projection_version
input_context_policy
output_schema
method_policy
```

The output schema defines the semantic answer space for that pass. For example, a `SubLemma` pass may allow:

```text
outcome = positive | negative | unresolved

positive:
    1..N sublemma assertions
    each with a node selection
    form selection
    optional gloss selection

negative:
    no SubLemma occurs in the eligible span

unresolved:
    reason / review category
```

The adjudicator works against an ephemeral item identifier and projected text. Durable source coordinates are attached only after the harness validates the answer.

## Versioned adjudication projection

The projection is the exact textual surface on which a judgment is made.

It is not an incidental call to `strip_tags`. It is a named, versioned transformation with two outputs:

```text
ProjectedView
    text
    segments
```

Each projection segment maps a half-open interval of the projected text to one or more parser-view/raw source intervals or to declared synthetic layout.

Conceptually:

```text
projected [0, 13)    → raw [1042, 1058)
projected [13, 14)   → synthetic/collapsed whitespace
projected [14, 39)   → raw [1071, 1102)
```

The exact implementation may use a finer event map rather than storing this literal structure, but it must support deterministic translation of projected selections back to source.

A projection version changes whenever the material or normalization visible to the adjudicator changes in a way that can affect a judgment or selection. Formatting that is provably outside the adjudication surface need not create a new version.

The record's `view.sha256` hashes the exact projected text for the adjudicated item under the named projection version.

## Context versus adjudicated material

An adjudicator may need surrounding context that is not itself being adjudicated.

The harness therefore distinguishes:

- **target projection** — the text whose positive/negative/unresolved outcome is recorded;
- **context projection** — optional neighboring entry, sense, rubrique, citation, or source material supplied to support the judgment.

Only the target projection bears the record's source anchor and view hash. Context is recorded by stable source references and may be included in prompt provenance, but it does not enlarge the adjudicated span merely because it was visible.

This prevents an LLM prompt from accidentally changing record identity whenever more context is supplied.

## Constituent selections and sub-spans

Semantic constituents such as a `SubLemma`'s `form` and `gloss` remain source-anchored sub-spans.

The adjudicator selects or quotes material in the **projection**, not in raw XML.

### Human authoring

A human UI may return projected start/end positions directly by text selection.

### LLM authoring

An LLM returns the exact projected substring for each required constituent, optionally with a small amount of neighboring projected context when uniqueness requires it. The LLM does not return byte offsets.

The harness then:

1. locates the selection in the target projection;
2. requires a unique match under the pass's matching policy;
3. converts the projected interval through the provenance map;
4. removes purely synthetic leading/trailing layout from the selected boundary;
5. produces the smallest raw interval covering the selected source-visible characters;
6. validates both raw endpoints as UTF-8 codepoint boundaries and as contained within the parent semantic node span.

If the selection has zero matches, multiple matches that cannot be disambiguated, or a projection-to-source mapping that cannot produce a valid constituent span, the harness does not guess. The outcome is escalated for review or re-authoring.

This avoids corpus-scale raw-text searching across XML markup, whitespace normalization, and patches.

## Semantic node interval validation

Before a positive structural record is committed, the harness validates node geometry against already applicable assertions.

Semantic node spans must be laminar:

- disjoint spans are valid;
- containment is valid;
- adjacency is valid;
- partial crossing overlap is invalid.

A new node that crosses an existing node creates a structural-conflict review item. The harness does not resolve the conflict by node-type precedence, and the renderer never receives unresolved crossing structure.

Qualification marker spans and qualification targets may overlap semantic nodes; the laminarity requirement applies to structural semantic nodes, not to all spans in the system.

## Human authoring

The human interface may be terminal-, browser-, or editor-based; the architecture does not require a particular UI.

It must nevertheless present the exact versioned target projection and return decisions through the same pass schema used by other methods. Human convenience fields such as headword, source line, entry context, and rendered neighboring senses are navigational only.

A human-authored record receives `method = "human"` and an adjudicator identifier. The harness, not the human, fills all mechanical provenance.

## LLM authoring

LLM adjudication is mediated by a versioned prompt definition owned by the pass.

The harness records at least:

```text
method          llm
model           exact model identifier
prompt_version  pass-controlled version
runtime         optional runtime/backend identifier
```

The prompt contains an ephemeral item id, the target projection, permitted context, the semantic question, and a machine-validated output schema. It must not expose raw source offsets as something the model is expected to manipulate.

Malformed model output, schema violations, or unmappable constituent selections are execution failures/review cases, not implicit negative adjudications.

Prompt/model iteration is evaluated against protected labeled data before a pass version is frozen for corpus-scale use. The 131 existing locution labels are retained as such an evaluation asset during development rather than immediately consumed as authoritative records.

## Rule authoring and bulk negatives

Deterministic rules use the same harness and record schema.

Rule-produced positive, negative, and unresolved outcomes are first-class adjudications when the rule genuinely establishes the claim it records. The harness may stream a complete eligible population and emit large numbers of canonical negative records without individual human review.

A rule may not translate `detector did not fire` into `negative` unless the rule's specification proves that non-detection establishes absence over that population. Heuristic silence is not adjudication.

Bulk rule records retain pass version, population version, method, rule/adjudicator identifier, anchors, and hashes exactly like human or LLM records.

This is how exhaustion remains economically viable for the ordinary case: coverage may contain hundreds of thousands of explicit negatives without requiring hundreds of thousands of human decisions.

## Segmentation completeness

`segmentation_complete` is authored only after the structural adjudication state for the target span supports the claim that no unresolved structural boundary remains under the current alternative-set version.

The harness may derive and write this closure record mechanically when its prerequisites are satisfied; it is not a free-form LLM judgment.

For structural alternative-set version 1, closure checks include the applicable `SubLemma` and `VoiceVariant` results, the ordered positive structural spans, residual spans, population eligibility, and absence of structural-conflict records.

Ordinary `Sense` remains a resolver derivation from this closure plus negative alternative results; the authoring harness does not ask an adjudicator to label residual material `Sense` merely because another class was absent.

## Qualification passes and variantes

A pass definition owns its eligible population explicitly.

For version 1, qualification passes whose phenomena occur at `<variante>` level include variantes. This includes the Lex-0 usage-property families when corresponding source labels are present there. The authoring harness enumerates those items from the universal census rather than relying on an indent-only model traversal.

Structural passes may exclude variantes or rubrique internals only through an explicit versioned population definition.

## Review and failure policy

The harness fails closed on:

- raw-anchor or projected-view mismatch;
- output-schema violation;
- zero/ambiguous constituent match after permitted disambiguation;
- invalid projection-to-source mapping;
- constituent span escaping its asserted node;
- crossing semantic-node intervals;
- invalid target reference;
- stale pass/population/projection version;
- rule output that violates the rule pass's declared decision contract.

A failure does not fall through to heuristic classification and does not silently become `negative`.

Review items preserve enough provenance to reproduce the attempted adjudication: item id, pass/version, source anchor, projection/version, method, prompt/model or rule identifier, returned answer, and failure category.

## Canonical record writing

Only the authoritative-store writer serializes committed JSONL.

It applies the canonical ordering and formatting rules in `adjudication-rendering.md`, computes all hashes from repository data, and performs an atomic replace of regenerated per-pass/per-letter files.

Direct hand editing of coordinates, hashes, or record ids is unsupported. A maintenance command may expose controlled re-anchoring or correction operations, but those operations pass through the same validators and canonical writer.

## Minimum v0.3 implementation

Before corpus-scale LLM adjudication begins, the following vertical slice must work on real development material:

```text
FlatNode source node
    ↓
SourceBlock + raw anchor
    ↓
target/context projection + provenance map
    ↓
SubLemma adjudication interaction
    ↓
validated constituent selections
    ↓
anchored canonical record
    ↓
resolved semantic representation
    ↓
TEI + SQLite
```

The same harness then supports `VoiceVariant`, qualification, relation, and later adjudication passes without changing the source identity or record-writing machinery.

The UI can remain minimal for v0.3. The non-negotiable part is the controlled provenance path from displayed text and semantic answer to durable record.
