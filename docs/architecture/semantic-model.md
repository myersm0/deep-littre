# Semantic model

The semantic layer: what a source block yields, how those facts are anchored, and how ordinary senses are derived. Source-position mechanics live in `source-representation.md`.

## A block is not a type

XMLittré `<indent>` is a source-layout container, not a semantic type. One source block may contain several independently true facts at once. The semantic layer therefore describes those facts directly rather than assigning one mutually exclusive label to the container.

A source block yields:

```text
0..N semantic nodes
0..N qualifications
0..N relations
explicit target references
unassigned/coarse remainder where adjudication is incomplete
```

## Why orthogonality is required

Adjudication is performed one semantic class at a time. Each adjudication pass must add information without invalidating settled facts from another pass.

A single enum cannot do that. In the sample, for example:

- `angoisse_s3.1` contains the register label *Familièrement.*, the multiword unit *Avaler des poires d'angoisse*, and its gloss;
- `boue_s2.2` contains the figurative label *Fig.* and the multiword unit *Bâtir sur la boue* with its gloss.

Forcing one label onto either block necessarily discards another true fact. The representation therefore allows a usage qualification and a form-bearing semantic node to coexist on the same material.

## Source structure and semantic structure are separate

Source objects answer questions such as:

- where is this material in XMLittré;
- what source element contains it;
- what raw bytes does it occupy;
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

The model may grow additional structural node types, but adding one also changes the set of passes closure must exhaust before an ordinary `Sense` can be derived. Existing verdicts for the older passes remain valid; blocks simply remain structurally open until the new alternative has been examined.

Containment is structural, not typal. A `VoiceVariant` may contain senses; a `SubLemma` may or may not; rubriques may contain semantic nodes. Node type does not encode whether a node can contain children.

There is no node type meaning "unclassified" or "not adjudicated". Those are workflow states represented by examination records.

## Structural alternatives

The current structural alternatives are `{SubLemma, VoiceVariant}`. Both are form-bearing;
`Sense` is not.

### VoiceVariant

A `VoiceVariant` is **a separately presented form-bearing pronominal or reflexive alternant of the
lemma that introduces or governs its own sense material.** Littré sometimes effectively opens a
subsidiary entry under a verb — a printed `SE …` form followed by its own senses — which is what
justifies giving it a node and serializing it entry-like.

It is deliberately narrower than the general voice/construction category:

- an explicit `SE + verb` form functioning as a new grammatical alternant → `VoiceVariant`;
- a printed reflexive transition that actually introduces such a form and subsequent senses → `VoiceVariant`;
- `v. réfl.` merely stating that the current lemma or sense is used reflexively → grammatical property;
- `Se dit …` prose with no separately recoverable form-bearing alternant → grammatical information;
- active, neutral, passive, impersonal and other construction shifts routed by `usg_gram_norms.toml` → grammatical `construction`, unless the source separately presents a new form-bearing variant.

The operative distinction is not reflexive-versus-other-construction. It is:

```text
separately form-bearing grammatical alternant  → VoiceVariant node
grammatical fact about a sense or form         → grammatical property
```

The two are orthogonal and routinely co-occur without duplication. `DISPENSER` variante 7 resolves as:

```text
VoiceVariant
    form = "Se dispenser"
    grammatical: pos=verb, valency=reflexive     (deterministic, from <nature>v. réfl.</nature>)
    definition: Être départi. Les honneurs se dispensent quelquefois au hasard.
```

The structural adjudication says a separately form-bearing variant is present. The deterministic
enrichment says what construction characterizes it. Neither is derivable from the other. By
contrast `ÉVADER (S')`, whose entry-header `<nature>v. réfl.</nature>` describes the whole lemma,
carries the grammatical property and no `VoiceVariant` node.

The pass is therefore narrowed by its **question**, not by its population: it draws on the same
`structural_blocks` population as `SubLemma` and asks whether the material introduces a separately
form-bearing pronominal or reflexive variant rather than merely stating a grammatical construction
or usage.

## Sub-lemma constituents

A `SubLemma` may carry constituent spans such as:

- `form`;
- `gloss`.

These are decomposition results inside the node's span. They are not node types and do not participate in structural-exhaustion accounting.

Constituents are generally not adjacent: Littré separates a form from its gloss with punctuation
that belongs to neither span. Durable adjudication stores their intervals in projected classifier
text. When a valid verdict is applied, those intervals are materialized to current raw spans inside
the node's raw extent; the material between the materialized form and gloss is therefore recoverable
as the node's `separator`. Constituent spans are retained through resolution into both outputs rather
than being reduced to their text, and no renderer may drop the separator or graft it onto a
constituent it does not belong to. A constituent's semantic text is reconstructed through the same
projection used for adjudication rather than by blindly slicing its raw interval, because a
contiguous source interval may legitimately cover interior markup.

A block may contain more than one sub-lemma. A node's primary span is contiguous; if shared or discontinuous material later requires representation, attach multiple explicit constituent/source spans rather than silently redefining `SourceSpan` as discontinuous. Constituent offsets are produced by the authoring harness from selections in a versioned projection with source provenance, not by asking an adjudicator to locate raw bytes.

Semantic node spans are laminar: two nodes are disjoint or one strictly contains the other. Distinct nodes with coincident primary spans and nodes with partial crossing overlap are structural conflicts requiring review; the resolver and renderers do not invent a precedence rule. For a valid contained set, the smallest strict containing semantic span is the structural parent.

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

`register` is deliberately absent: it spans several Lex-0 types at once, so printed labels route directly to the axis or axes they belong to. Compound labels such as *familièrement et fig.* may produce multiple qualifications of different axes.

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

Containment is the deterministic default: a marker governs the innermost resolved node whose span
contains it. That is a stated geometric rule, not a heuristic guess, so it needs no adjudication
and the absence of a record never becomes a claim.

The `qualification_scope` pass records **departures** from that default. Its question is whether
any marker in the material governs something other than the block containing it; a negative
outcome is the positive statement that every marker here scopes by containment. A positive
outcome carries scope assertions naming the printed marker and the projected span of the material it
governs — a span rather than a node id, because the node it lands on may be derived at resolution
and have no durable identity. Valid records materialize both projected intervals to current raw
spans before resolution.

A scope adjudication moves **where** a marker applies, never **what** it means. The type and norm
stay deterministic products of the committed normalization tables, and a test asserts the full set
of qualification facts is byte-identical before and after a scope record is applied. The marker
selection must land on a printed `<semantique>` or `<nature>` element: an adjudicator may say how
far a printed label reaches, not invent a label the source does not print.

## Adjudication identity and stale detection

Durable adjudication identity is semantic rather than positional. A record stores the current raw block
span `(file, start_byte, end_byte)` only as a fast locator and stores one `surface_sha256` over the
canonical material actually presented for classification.

The classification surface includes the projected target text, target kind, explicit qualification
markers, and deterministic citation context. Context is therefore evidence: changing a citation can
make a structural verdict stale even when the target block text itself is unchanged. This is
intentionally conservative.

Semantic selections inside the target — node, form, gloss, residual, scope marker, and scope target —
are stored as half-open byte intervals in projected classifier text. They are translated to current
parser-view/raw coordinates only after the record's classification surface has been validated.

Application proceeds conservatively:

1. inspect the block at the stored locator;
2. if it is still an eligible block, require its classification surface hash to match;
3. if the old locator no longer names a block, recover only a unique same-file eligible block with
   the same surface hash;
4. otherwise mark the verdict stale.

If an eligible block still occupies the old locator but its surface changed, no fallback search is
performed. A development build reports and skips stale verdicts; a strict release rejects them.
Malformed record geometry is a store-integrity error, not a stale verdict.

Line number, headword, source ordinal, and generated `xml:id` remain useful navigation fields but do
not bear adjudication identity. Detailed transform mapping is defined in `source-representation.md`.

## Authoritative adjudication records

Workflow meaning lives outside the semantic tree.

For every eligible block/span and pass, the authoritative store distinguishes:

- positive — examined and the class applies;
- negative — examined and the class does not apply;
- unresolved — examined but no decision is made;
- absent record — not examined.

An absent record is the ordinary intermediate state and is never read as a negative.

The authoritative store is a committed input. Generated `littre.db` may mirror it for queries but is not the only durable home of judgments.

## Census and eligible populations

Coverage begins with a source-derived `SourceBlock` census independent of semantic traversal.

Initial `SourceBlock` kinds include:

- ordinary `<indent>`;
- `<variante>`;
- `<résumé>`-internal `<indent>` and `<variante>`;
- rubrique-internal `<indent>` and `<variante>`;
- `<entete>/<nature>`.

Containment is decided by ancestry, not element name, and résumé ancestry is consulted for both `<indent>` and `<variante>`. Résumé material summarizes senses represented elsewhere in the entry and is excluded from the structural population.

`<prononciation>` is source data but is excluded from the `SourceBlock` census; it is form/commentary data handled by its own pipeline path.

The `SourceBlock` census is universal over the defined adjudication-relevant block population, not over all XMLittré content. It answers “which source blocks exist for adjudication?”. Each adjudication pass declares a versioned eligible population drawn from that census.

A pass can therefore state honestly that it has completed all ordinary indents while deliberately deferring rubrique internals, without making deferred blocks disappear from the denominator. Qualification passes whose phenomena occur at `<variante>` level include variantes in their version-1 eligible populations; the census does not merely count them and then silently exclude them from usage adjudication.

## Deriving ordinary `Sense`

No single pass asserts that whatever it did not recognize must be an ordinary sense.

Ordinary `Sense` is derived only by exhaustion of the current structural alternatives, presently:

```text
{SubLemma, VoiceVariant}
```

A persisted examination target is a census `SourceBlock`. Each structural pass examines the whole
block. A negative result establishes that alternative as absent throughout the block. A positive
result is exhaustive: asserted node spans plus explicit residual spans must completely partition the
projected target. The harness checks that partition when authoring and application revalidates the
persisted geometry before resolution.

Residual spans are therefore closure evidence, not independently addressable adjudication targets,
and the store holds no per-residual verdicts. For closure, every current structural pass must have an
applicable non-unresolved result and the combined assertions must be structurally compatible. If any
pass is absent, stale, unresolved, or conflicting, ordinary `Sense` is not derived.

### Residuals are closure units, not node extents

A residual span establishes the ordinary content of a closed structural container. It does not
itself become a `Sense` node. For

```text
prose A [SubLemma] prose B
```

the resolved structure is one contiguous enclosing `Sense` whose span contains the positive
child node:

```text
Sense span:  [-------------------------]
SubLemma:              [-------]
```

with `prose A` and `prose B` supplying the definition content. This is what laminarity permits
and what the Lex-0 nesting of `<entry type="relatedEntry"> `inside `<sense>` requires. Deriving a
separate `Sense` per residual would manufacture discontinuous senses merely because a nested
entry interrupts the definition.

Closure may therefore derive one enclosing `Sense` containing positive child nodes; residual
spans themselves need not become separate `Sense` nodes.

The derivation applies to the block's **direct content** — what remains once asserted structural children are carved out — and is valid only where the block is eligible for every current structural pass, every pass has an applicable non-unresolved verdict, and positive partitions have been validated.

If a future release adds a new structural alternative, closure immediately requires that new pass as well. Existing verdict records for older passes do not become false or stale merely because the set grew; previously derived senses simply cease to close until the new alternative has been examined.

## Partial adjudication and coarse truth

Incomplete adjudication does not block serialization.

Where finer structure has not been established, the renderer may emit coarse but true structure such as a `<sense><def>…</def></sense>`. This is a serialization fallback, not a positive semantic assertion that the material has been adjudicated as an ordinary `Sense`.

Once a sub-lemma is established, it renders as a nested `<entry type="relatedEntry">` inside the parent sense. Qualifications render on their explicit targets.

Workflow state such as "unexamined" is not published as `ana="unclassified"`.

## Published identifiers

Generated TEI `xml:id` values are rendering identifiers, not adjudication identities.

Cross-release `xml:id` stability is not promised before 1.0. Adjudication proceeds by classification surfaces, projected selections, a locator, and opaque internal ids, so semantic work is not coupled to positional TEI identifiers.

If stable public ids become a requirement, that is a separate release-contract decision.

## Passes, not a classification task

There is no single corpus-wide "indent classification" task. There are independent adjudication passes for semantic classes and property families. Each may be human-, LLM-, or rule-driven; each can be calibrated against ground truth; and each adds facts monotonically without erasing facts established by another.

A deterministic negative outcome is first-class where a rule genuinely establishes absence. The absence of a heuristic trigger is not itself a negative adjudication.

XMLittré's own locution tagging is not an estimate of the sub-lemma population: the 25-entry development corpus already contains untagged multiword units embedded in ordinary definition prose.
