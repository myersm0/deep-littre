# Semantic model: span-anchored adjudication

Status: **normative semantic-layer specification for v0.3**.

This document replaces the v0.2 `IndentRole` ontology. Implementation sequencing and source-position mechanics live in `rewrite-v0.3.md` and `source-representation.md`.

## Core result

The finished model has no `IndentRole`.

XMLittré `<indent>` is a source-layout container, not a semantic type. One source block may contain several independently true facts at once. The semantic layer therefore describes those facts directly rather than assigning one mutually exclusive label to the container.

A source block yields:

```text
0..N semantic nodes
0..N qualifications
0..N relations
explicit target references
unassigned/coarse remainder where adjudication is incomplete
```

The v0.2 role hierarchy may appear in historical releases and import adapters but not in the durable v0.3 representation.

## Why orthogonality is required

Adjudication is performed one semantic class at a time. Each adjudication pass must add information without invalidating settled facts from another pass.

A single enum cannot do that. In the sample, for example:

- `angoisse_s3.1` contains the register label *Familièrement.*, the multiword unit *Avaler des poires d'angoisse*, and its gloss;
- `boue_s2.2` contains the figurative label *Fig.* and the multiword unit *Bâtir sur la boue* with its gloss.

Treating either block as only `RegisterLabel`, `Figurative`, or `Locution` necessarily discards another true fact. The v0.3 representation allows the usage qualification and form-bearing semantic node to coexist.

## Source structure and semantic structure are separate

Source objects answer questions such as:

- where is this material in XMLittré;
- what source element contains it;
- what raw bytes does it occupy;
- was a boundary introduced by a patch;
- what rubrique or entry contains it.

Semantic objects answer questions such as:

- is this span a sub-lemma;
- is this a voice variant;
- which span or node does a usage label qualify;
- is this a cross-reference;
- what structure should the renderers derive.

Semantic adjudication never mutates or reparents the source tree.

## Node axis

A semantic node has at most one node type.

The initial structural node types are:

- `Sense` — not form-bearing;
- `SubLemma` — form-bearing;
- `VoiceVariant` — form-bearing.

The model may grow additional node types only by versioning the structural alternative set used for exhaustion.

Containment is structural, not typal. A `VoiceVariant` may contain senses; a `SubLemma` may or may not; rubriques may contain semantic nodes. Node type does not encode whether a node can contain children.

There is no node type meaning "unclassified" or "not adjudicated". Those are workflow states represented by examination records.

## Sub-lemma constituents

A `SubLemma` may carry constituent spans such as:

- `form`;
- `gloss`.

These are decomposition results inside the node's span. They are not node types and do not participate in structural-exhaustion accounting.

A block may contain more than one sub-lemma. A node's primary span is contiguous; if shared or discontinuous material later requires representation, attach multiple explicit constituent/source spans rather than silently redefining `SourceSpan` as discontinuous. Constituent offsets are produced by the authoring harness from selections in a versioned projection with source provenance, not by asking an adjudicator to locate raw bytes.

Semantic node spans are laminar: two nodes are disjoint or one contains the other. Partial crossing overlap is a structural conflict requiring review; the resolver and renderers do not invent a precedence rule.

## Qualifications

Qualifications are zero-or-more facts that name their target explicitly.

Usage axes are named after the TEI Lex-0 closed typology:

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

`register` is deliberately absent. It was a v0.2 source-side catch-all spanning several Lex-0 types. Compound labels such as *familièrement et fig.* may produce multiple qualifications of different axes.

`proverbial` is not an axis. It is a value under `meaningType`.

The grammatical family is separate from usage qualifications and serializes through `<gramGrp>/<gram>`. Its internal ontology may distinguish POS, gender, valency, construction, government, inflectional information, and other grammatical properties as empirical work requires.

## Relations

A cross-reference is a relation, not a qualification.

A relation points from a node/span/rubrique to another lexical object or textual target. Cross-reference type and target resolution are stored as relation data and serialize through `<xr>/<ref>` where possible.

## Scope and target references

A qualification is never merely "on the block". Its scope is represented by an explicit target reference:

- span;
- semantic node;
- sibling-node range;
- rubrique.

The transition-resolution labels inherited from v0.2 — strong, medium, intra-sense, zero, and citation veto — may survive as inference metadata for the voice/transition pass. They do not constitute the scope representation itself.

## Anchoring

Durable adjudication identity is based on immutable raw source spans, not generated sense ids or line numbers.

The canonical anchor is:

```text
(file, start_byte, end_byte)
```

with a half-open raw UTF-8 interval `[start_byte, end_byte)`.

Each adjudication stores:

1. a raw-anchor hash proving that the same upstream material still occupies that span;
2. a versioned adjudicated-view hash proving that the target material shown to the adjudicator has not changed semantically beneath a stable raw anchor.

Context shown alongside the target does not enlarge the anchor or participate in record identity, but its versioned projection hashes participate in validity. A context change marks the adjudication stale/reviewable until reconfirmed. For LLM adjudication, the authoring harness also records a verification hash of the fully rendered model input.

Line number, headword, source ordinal, and generated `xml:id` are useful navigation fields but do not bear adjudication identity.

Detailed transform mapping and XML.jl mechanics are defined in `source-representation.md`.

## Failing closed

An old judgment must never silently migrate onto different text.

If either target check fails, application of the record is an error. The pipeline does not warn and fall back to a heuristic answer. A context-hash mismatch preserves record identity but changes validity to stale/reviewable.

Re-anchoring is an explicit maintenance operation that updates the record after confirmation. The record's opaque `record_id`/`node_id` may survive re-anchoring even though its source coordinates change.

## Authoritative adjudication records

Workflow meaning lives outside the semantic tree.

For every eligible block/span and pass, the authoritative store distinguishes:

- positive — examined and the class applies;
- negative — examined and the class does not apply;
- unresolved — examined but no decision is made;
- absent record — not examined.

This distinction replaces the v0.2 `Unclassified` sentinel as the coverage mechanism.

The authoritative store is a committed input. Generated `littre.db` may mirror it for queries but is not the only durable home of judgments.

## Census and eligible populations

Coverage begins with a source-derived `SourceBlock` census independent of semantic traversal.

Initial `SourceBlock` kinds include:

- ordinary `<indent>`;
- `<variante>`;
- rubrique-internal `<indent>`;
- `<entete>/<nature>`.

`<prononciation>` is source data but is excluded from the `SourceBlock` census; it is form/commentary data handled by its own pipeline path.

The `SourceBlock` census is universal over the defined adjudication-relevant block population, not over all XMLittré content. It answers “which source blocks exist for adjudication?”. Each adjudication pass declares a versioned eligible population drawn from that census.

A pass can therefore state honestly that it has completed all ordinary indents while deliberately deferring rubrique internals, without making deferred blocks disappear from the denominator. Qualification passes whose phenomena occur at `<variante>` level include variantes in their version-1 eligible populations; the census does not merely count them and then silently exclude them from usage adjudication.

## Deriving ordinary `Sense`

No single pass asserts that whatever it did not recognize must be an ordinary sense.

Ordinary `Sense` is derived only by exhaustion of the current structural alternatives.

Structural alternative-set version 1 is:

```text
{SubLemma, VoiceVariant}
```

`segmentation_complete` belongs to **closure protocol version 1**; it is not a structural alternative. For a residual span:

```text
SubLemma?                negative
VoiceVariant?            negative
segmentation_complete    true
----------------------------------
ordinary Sense           derivable
```

Structural adjudication passes are exhaustive extraction over their target span when their pass contract declares the result exhaustive. A positive result may therefore establish one or more positive node spans **and** explicit residual target spans. When extraction is exhaustive, the harness may materialize the corresponding negative result for that same alternative on each residual span without a second deliberation. If extraction is unresolved or non-exhaustive, no such negative is implied.

Residual spans are then evaluated under the remaining structural alternatives. Positive and negative outcomes can therefore coexist within one enclosing source block while applying to different target spans.

The derivation is valid only where the residual span was eligible for every alternative pass and no result is unresolved. `segmentation_complete` asserts that all structural boundaries and residuals have been accounted for under the current alternative set and closure protocol.

If a future release adds a new structural alternative, it defines a new alternative-set version. Older derived senses do not silently inherit the stronger claim.

## Partial adjudication and coarse truth

Incomplete adjudication does not block serialization.

Where finer structure has not been established, the renderer may emit coarse but true structure such as a `<sense><def>…</def></sense>`. This is a serialization fallback, not a positive semantic assertion that the material has been adjudicated as an ordinary `Sense`.

Once a sub-lemma is established, it renders as a nested `<entry type="relatedEntry">` inside the parent sense. Qualifications render on their explicit targets.

Workflow state such as "unexamined" is not published as `ana="unclassified"`.

## Published identifiers

Generated TEI `xml:id` values are rendering identifiers, not adjudication identities.

v0.3 does not promise cross-release `xml:id` stability before 1.0. Adjudication proceeds by source anchors and opaque internal ids, so semantic work is not coupled to positional TEI identifiers.

If stable public ids become a requirement, that is a separate release-contract decision.

## Mapping from v0.2 concepts

| v0.2 concept | v0.3 representation |
|---|---|
| `Figurative` | qualification `meaningType=figurative` |
| `RegisterLabel` | one or more typed Lex-0 qualifications; never `register` |
| `DomainLabel` | qualification `domain=<norm>` |
| `NatureLabel` | grammatical property/properties |
| `CrossReference` | relation |
| `Proverb` | usually `SubLemma`/sense structure plus `meaningType=proverbial` |
| `VoiceTransition` | `VoiceVariant` when form-bearing; otherwise grammatical qualification |
| `Locution` | `SubLemma` |
| `Unclassified` | no semantic type; examination/coverage state lives in records |
| `Continuation`, `Elaboration` | no successor; historical documented values never produced by the classifier |

`RubriqueKind` was already independent of `IndentRole` and remains source/structural vocabulary rather than a node-axis value.

## Consequence for the adjudication programme

There is no single corpus-wide "indent classification" task.

There are independent **adjudication passes** for semantic classes and property families. Each can be human-, LLM-, or rule-driven, can be calibrated against ground truth, and adds facts monotonically without erasing facts from other passes. Bulk deterministic negative outcomes are first-class where a rule genuinely establishes absence; lack of a heuristic trigger is not by itself a negative adjudication.

A historically reported population of 131 XMLittré locution-tagged items should be retained as an audit/reference artifact until its provenance and quality are reviewed. It is **not assumed to be human-adjudicated ground truth**. In any case, the 25-entry sample already demonstrates untagged multiword units embedded in ordinary definition prose, so XMLittré's locution tag count is not an estimate of the sub-lemma problem.
