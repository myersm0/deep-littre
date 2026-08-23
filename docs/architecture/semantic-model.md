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

Adjudication is performed one semantic class at a time. Each pass must add information without invalidating settled facts from another pass.

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

A block may contain more than one sub-lemma. A node's primary span is contiguous; if shared or discontinuous material later requires representation, attach multiple explicit constituent/source spans rather than silently redefining `SourceSpan` as discontinuous.

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
2. a versioned adjudicated-view hash proving that the material shown to the adjudicator has not changed semantically beneath a stable raw anchor.

Line number, headword, source ordinal, and generated `xml:id` are useful navigation fields but do not bear adjudication identity.

Detailed transform mapping and XML.jl mechanics are defined in `source-representation.md`.

## Failing closed

An old judgment must never silently migrate onto different text.

If either source check fails, application of the record is an error. The pipeline does not warn and fall back to a heuristic answer.

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

Coverage begins with a source-derived universal census independent of semantic traversal.

Initial census-relevant source blocks include:

- ordinary `<indent>`;
- `<variante>`;
- rubrique-internal `<indent>`;
- `<entete>/<nature>`.

`<prononciation>` is excluded from this qualification-bearing block census; it is form/commentary data handled by its own pipeline path.

The universal census answers "what material exists". Each adjudication pass declares a versioned eligible population drawn from that census.

A pass can therefore state honestly that it has completed all ordinary indents while deliberately deferring rubrique internals, without making deferred blocks disappear from the denominator.

## Deriving ordinary `Sense`

No single pass asserts that whatever it did not recognize must be an ordinary sense.

Ordinary `Sense` is derived only by exhaustion of the current structural alternatives.

For structural alternative-set version 1:

```text
SubLemma?          negative
VoiceVariant?      negative
segmentation       complete
--------------------------------
ordinary Sense     derivable
```

The derivation is valid only where the span was eligible for every alternative pass and no result is unresolved.

`segmentation_complete` is a closure assertion that all structural boundaries in the eligible material have been accounted for under the current alternative set. It is not another semantic node type.

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

There are independent passes for semantic classes and property families. Each pass can be calibrated against ground truth, including LLM-assisted in-context judgments, and can add facts monotonically without erasing facts from other passes.

The 131 historically tagged locutions are therefore not the estimated size of the sub-lemma problem; the 25-entry sample already demonstrates untagged multiword units embedded in ordinary definition prose. Corpus sizing must come from the actual adjudication pass rather than XMLittré's locution tag count.
