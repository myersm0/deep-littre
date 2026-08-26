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
- records the opaque decision-procedure identity supplied with the verdict;
- emits canonical JSONL through the authoritative-store writer;
- fails closed to a review queue when a decision cannot be mapped or validated unambiguously.

The harness does **not** infer semantic answers that the verdict did not establish.

Store initialization is explicit rather than a side effect of reading or building. `initialize_store!(harness)` creates `manifest.toml` only for a store that contains no adjudication records and has no existing manifest. Ordinary resolution never rewrites authoritative store metadata.

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
exhaustive_extraction
input_context_policy
output_schema
```

`exhaustive_extraction` declares whether a positive examination means "these are all of them within
the target" or merely "here is one". It is a property of the question, not of an individual verdict,
so the harness enforces it at commit: a pass that performs exhaustive extraction rejects a positive
without the claim, and a pass that does not rejects the claim outright rather than storing a field
nothing will read. Version 1 declares it true for `sublemma` and `voice_variant`, false for
`qualification_scope`.

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

The event map distinguishes literal source copies from decoded XML references and synthetic layout. A decoded entity or numeric character reference is source-backed but non-linear: the projected character maps to the complete reference syntax in the parser view.

A projection version changes whenever the material or normalization visible to the adjudicator changes in a way that can affect a judgment or selection. Formatting that is provably outside the adjudication surface need not create a new version.

The record's `view.sha256` hashes the exact projected text for the adjudicated item under the named projection version.

## Context versus adjudicated material

An adjudicator may need surrounding context that is not itself being adjudicated.

The harness therefore distinguishes:

- **target projection** — the text whose positive/negative/unresolved outcome is recorded;
- **context projection** — optional neighboring entry, sense, rubrique, citation, or source material supplied to support the judgment.

Only the target projection bears the record's durable anchor and target-view hash and therefore determines record identity. Context does not enlarge the adjudicated span merely because it was visible.

Context is recorded as provenance — a source reference and a role — and must lie inside the record's own raw span. The record's raw-anchor hash therefore already covers the context bytes, so a change to them fails the record without a second check. Context drawn from outside the target span would not be covered and would need one; no pass draws context that way today.

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

The positive examination records A and B plus the explicit residual span between them. The residual is **evidence for the exhaustion claim**, not a target of its own: no per-residual record is written, and none is needed. A block-level result already determines every residual within the block, since an exhaustive positive establishes its alternative on the asserted spans and absent everywhere else, and a negative establishes it absent throughout.

Persisted examination targets are therefore census `SourceBlock`s. Positive and negative outcomes for *different alternatives* coexist over one block, and the resolver reads them together; they are not distributed across sub-block targets.

Exhaustion is checked rather than trusted, and checked **at commit**. The harness requires every
source-visible character of the projected target to be claimed by an asserted node span or an
explicit residual span, and rejects the verdict otherwise — while there is still an item to
re-author, rather than leaving a review row to be discovered at the next full build. The resolver
repeats the check for records written by anything that bypassed the harness.

This explicit residual contract makes exhaustion economical without weakening its semantics.

## Semantic node interval validation

Before a positive structural record is committed, the harness validates node geometry against already applicable assertions.

Semantic node spans must be laminar:

- disjoint spans are valid;
- strict containment is valid and determines semantic parentage;
- adjacency is valid;
- coincident spans for distinct nodes are invalid;
- partial crossing overlap is invalid.

Before commit, a structural pass is checked both internally and against the latest applicable record from every other structural pass on the same target. A new coincident or crossing node creates a `structural_conflict` review item. The harness does not resolve the conflict by node-type precedence, and the renderer never receives unresolved crossing structure.

Qualification marker spans and qualification targets may overlap semantic nodes; the laminarity requirement applies to structural semantic nodes, not to all spans in the system.

## Verdict producers

The harness is method-agnostic by design. It presents an item and ingests a verdict; it does not
know or record how the verdict was reached.

A producer receives an ephemeral item id, the exact versioned target projection, and whatever
context the pass permits. It returns a verdict expressed as selections in that projected text,
against the pass's output schema. Raw source offsets are never exposed as something a producer is
expected to manipulate.

The harness then anchors the verdict, resolves selections to raw spans, computes every hash, mints
every identifier, validates geometry, and writes canonically. The record carries only
`decision_procedure` — an opaque name for the producing process — and an optional opaque
`decision_reference` into that process's own records.

Everything about *how* verdicts are produced lives outside this repository: question sets, prompt
definitions and their versions, model identities and runtimes, per-question responses, and any
deterministic combiner that turns responses into a verdict. That separation is deliberate. A
producer may query language models and analyze their answers deterministically, may be a rule, may
be a person, or may be a hat; the pipeline consumes the result identically. Re-deriving verdicts
from retained evidence, and auditing how a verdict changed, are that process's responsibilities.

Malformed producer output, schema violations, and unmappable constituent selections are execution
failures and review cases, never implicit negative verdicts.

The store holds current verdicts, not their history. At most one record may exist per target per
pass; a second is a store integrity failure rather than a revision. Superseding a verdict means
regenerating the pass from the producer's current output.

Producer iteration should be evaluated against reviewed labeled data when such data exists. The historically reported locution-tag/label population is retained for provenance review and possible later evaluation use, but it is not assumed to be adjudicated ground truth until that provenance is established.

## Rule authoring and rule-established negatives

Deterministic rules use the same harness and record schema.

Rule-produced positive, negative, and unresolved outcomes are first-class adjudications when the rule genuinely establishes the claim it records. The harness may stream a complete eligible population and emit large numbers of canonical negative records without individual human review.

A rule may not translate `detector did not fire` into `negative` unless the rule's specification proves that non-detection establishes absence over that population. Heuristic silence is not adjudication.

Whether a rule's outcomes are committed one record per target or in some compressed form is
deliberately unsettled; see `adjudication-rendering.md`. A compressed representation was specified
and built before any rule pass existed to produce one, and was removed unused. The shape of the
first real rule pass should determine it.

## Segmentation completeness

`segmentation_complete` belongs to closure protocol version 1, not to the structural alternative set. It is authored only after the structural adjudication state for the target span supports the claim that no unresolved structural boundary remains under the current alternative-set version.

Closure is derived by the resolver from adjudication state rather than committed as a record per block; it is not a free-form LLM judgment and is not authored by hand.

Structural alternative-set version 1 is `{SubLemma, VoiceVariant}`. Closure protocol version 1 checks the applicable results for both alternatives, the ordered positive structural spans, explicit residual spans, population eligibility, exhaustive-extraction status, and absence of structural-conflict records.

Ordinary `Sense` remains a resolver derivation from this closure plus negative alternative results; the authoring harness does not ask a producer to label residual material `Sense` merely because another class was absent. The derivation concerns the block's direct content, while the derived node's span is the enclosing block.

## Qualification passes and variantes

A pass definition owns its eligible population explicitly.

A pass names its population; it does not inherit another pass's. Version 1 declares two:

```text
structural_blocks     v1   indent, variante
qualification_blocks  v1   indent, variante
```

They coincide in extent today and are still named separately, because they answer different
questions. Qualification markers also occur in rubrique-internal blocks, and widening the
qualification population to reach them should be a population version bump rather than a change to
what the structural passes mean.

Both include variantes, since the phenomena of both occur there. Both exclude résumé material,
which summarizes senses represented elsewhere in the entry, and rubrique internals, which are
deferred rather than denied — the census continues to count them, so a deferred block never
disappears from the denominator.

The authoring harness enumerates a population from the `SourceBlock` census rather than from a
model traversal. Excluding a census kind from a population requires naming it in that population's
definition; a new census kind fails the build rather than being silently admitted or dropped.

## Review and failure policy

The harness fails closed on:

- raw-anchor or projected-view mismatch;
- a context reference escaping the record's own raw span;
- output-schema violation;
- zero/ambiguous constituent match after permitted disambiguation;
- invalid projection-to-source mapping;
- constituent span escaping its asserted node;
- crossing semantic-node intervals;
- invalid target reference;
- stale pass/population/projection version;
- rule output that violates the rule pass's declared decision contract.

A target-anchor or target-view failure does not fall through to heuristic classification and does not silently become `negative`.

### Build-time failure policy

Failing closed governs whether a judgment is **applied**, not necessarily whether the build
terminates:

- **raw-anchor/hash mismatch → fatal.** The store no longer names the corpus it claims to name.
  This is a source/store integrity failure and aborts the build.
- **target-view mismatch → quarantine.** The adjudication is not applied, a review item is
  created, and an ordinary development build continues.
- **release build → coverage gates still fail** if quarantining leaves a required population
  incomplete.

A quarantined record therefore never falls through to a heuristic answer, which is the original
requirement, while a single stale judgment does not prevent rebuilding the rest of the corpus. A
`--strict-adjudications` flag makes any quarantine fatal.

Review items preserve enough provenance to reproduce the attempted adjudication: item id, pass/version, source anchor, projection/version, decision procedure, returned answer, and failure category.

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
