# Adjudication authoring harness

Status: **normative v0.3 authoring specification**.

## Purpose

The authoring harness is the controlled boundary between an adjudicator and the authoritative adjudication store.

An adjudicator may be a human, an LLM, or a deterministic rule. The adjudicator decides semantic questions. The harness owns source identity, projections, source-coordinate translation, hashes, record ids, validation, canonical serialization, and review escalation.

No human or LLM is asked to author `start_byte`, `end_byte`, raw hashes, view hashes, projection versions, or JSONL records directly.

```text
source representation + SourceBlock census
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
    exhaustive = true | false
    1..N sublemma assertions
    each with a node selection
    form selection
    optional gloss selection
    0..N explicit residual target spans

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

Only the target projection bears the record's durable anchor and target-view hash and therefore determines record identity. Context does not enlarge the adjudicated span merely because it was visible.

Context **does participate in validity** when it was shown to the adjudicator. Each context item records a stable source reference plus its projection name/version and projected-context hash. If that context later changes, the adjudication retains its identity but is marked `stale_context` and reviewable; it must be reconfirmed before counting as current completed coverage.

For LLM adjudication, the harness also stores a hash of a canonical serialization of the fully rendered model input actually sent to the model. The committed prompt definition/version plus the recorded target projection, context references, output schema, and model/runtime metadata must be sufficient to reconstruct that input; the hash verifies the reconstruction. This complements `prompt_version` without making context part of source identity.

This separates the stable identity question “what span was adjudicated?” from the validity question “was the evidence shown to the adjudicator still the same?”.

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

## Exhaustive structural extraction and residuals

A structural adjudication pass may define its examination as exhaustive extraction over the target span. For the `SubLemma` pass, a positive result can therefore mean “these are all SubLemmas in this target”, not “the entire target is a SubLemma”.

For example:

```text
[sublemma A] [ordinary candidate remainder] [sublemma B]
```

The positive examination records A and B plus the explicit residual span between them. If the adjudicator asserts `exhaustive = true`, the harness may mechanically materialize `SubLemma = negative` for that residual without asking the same question again. If the result is unresolved or `exhaustive = false`, no residual negative is implied.

Each residual remains a first-class target for the **other** structural alternatives. Positive and negative outcomes can therefore coexist inside one enclosing `SourceBlock` while applying to different spans. Nested or recursively selected targets use the same contract.

This explicit residual contract makes exhaustion economical without weakening its semantics.

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

The prompt contains an ephemeral item id, the target projection, permitted context, the semantic question, and a machine-validated output schema. It must not expose raw source offsets as something the model is expected to manipulate. The harness hashes a canonical serialization of the fully rendered model input actually sent and records that hash with the resulting adjudication.

Malformed model output, schema violations, or unmappable constituent selections are execution failures/review cases, not implicit negative adjudications.

Prompt/model iteration should be evaluated against reviewed labeled data when such data exists. The historically reported locution-tag/label population is retained for provenance review and possible later evaluation use, but it is not assumed to be human-adjudicated ground truth until that provenance is established.

## Rule authoring and bulk negatives

Deterministic rules use the same harness and record schema.

Rule-produced positive, negative, and unresolved outcomes are first-class adjudications when the rule genuinely establishes the claim it records. The harness may stream a complete eligible population and emit large numbers of canonical negative records without individual human review.

A rule may not translate `detector did not fire` into `negative` unless the rule's specification proves that non-detection establishes absence over that population. Heuristic silence is not adjudication.

Bulk rule records retain pass version, population version, method, rule/adjudicator identifier, anchors, and hashes exactly like human or LLM records.

This is how exhaustion remains economically viable for the ordinary case: coverage may contain hundreds of thousands of explicit negatives without requiring hundreds of thousands of human decisions.

## Segmentation completeness

`segmentation_complete` belongs to closure protocol version 1, not to the structural alternative set. It is authored only after the structural adjudication state for the target span supports the claim that no unresolved structural boundary remains under the current alternative-set version.

The harness may derive and write this closure record mechanically when its prerequisites are satisfied; it is not a free-form LLM judgment.

Structural alternative-set version 1 is `{SubLemma, VoiceVariant}`. Closure protocol version 1 checks the applicable results for both alternatives, the ordered positive structural spans, explicit residual spans, population eligibility, exhaustive-extraction status, and absence of structural-conflict records.

Ordinary `Sense` remains a resolver derivation from this closure plus negative alternative results; the authoring harness does not ask an adjudicator to label residual material `Sense` merely because another class was absent.

## Qualification passes and variantes

A pass definition owns its eligible population explicitly.

For version 1, qualification passes whose phenomena occur at `<variante>` level include variantes. This includes the Lex-0 usage-property families when corresponding source labels are present there. The authoring harness enumerates those items from the `SourceBlock` census rather than relying on an indent-only model traversal.

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

A target-anchor or target-view failure does not fall through to heuristic classification and does not silently become `negative`. A context-hash mismatch is handled separately as `stale_context`: identity is retained, but the record is reviewable and excluded from current completed coverage until reconfirmed.

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
