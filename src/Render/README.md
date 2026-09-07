# Render

Two serializers of one resolved representation. Neither classifies an indent, decides whether prose is a sub-lemma, infers scope, turns an underdetermined node into a claim, or publishes workflow state as semantic markup. Anything a renderer would have to work out is worked out in `Resolve` and carried, because both outputs must agree and neither is permitted to infer.

The normative renderer contract is summarized in `docs/architecture/adjudication-rendering.md`; this README records implementation details and the schema behavior that motivates them.

`tei.jl` and `sqlite.jl` are independent serializers over the same `Resolve` output. `tei.jl` names every `xml:id` in a first pass, `assign_names`, before the render walk begins: a cross-reference can only point at a target whose identifier is already known, so the walk itself mints nothing. A form-bearing node needs two names, one for its nested `<entry>` and one for the `<sense>` inside it, and a reference to that node resolves to the entry.

Partially adjudicated material renders coarsely but truthfully. A block with no resolved finer structure may appear as `<sense><def>…</def></sense>` without that implying anyone established an ordinary sense. No `ana="unclassified"` marker is emitted.

## TEI

Serialization plus mechanical escaping and formatting. Structural indentation and line breaks exist so the corpus is inspectable by hand; formatting never inserts whitespace inside a definition, quotation, segment, orthographic form, pronunciation, emphasis, or reference payload.

Schema conformance is settled empirically, not from the specification. The published RNG diverges from the TEI Lex-0 paper on several load-bearing points — a closed `cit/@type` vocabulary, no `<dictScrap>`, no `@type` on `<sense>`, RFC 3066 language-tag datatypes — and the schema wins. `test/probe_lex0.xml` isolates one construct per minimal entry with controls, and a surprising validator result gets a new probe entry before anyone debugs by hand.

The context-sensitivity that follows from that is easy to get wrong. `<xr>` is admitted by `<def>` and `<quote>` but not by `<seg>`, which takes a bare `<ref>`; `<note>` cannot hold `<cit>` at all, which is why rubrique citations are lifted to entry level while rubrique prose stays in a note. Neither is inferable from the element names, and both were found by probing rather than by reading.

`xml:id` values are rendering identifiers. They are positional and legible — `angoisse_s1`, `angoisse_s3.2` — because a collision counter produced names in which the first sibling had no number and depth was spelled by repeating `_s`. Dots are legal, since `xml:id` is an `xsd:ID` and therefore an NCName. Readability is not durability: a positional id moves whenever adjudication regroups the material under it, and cross-release stability is not promised before 1.0.

## SQLite

A queryable mirror of the same resolved model and provenance. `node_type` is null exactly where the semantic type is underdetermined, so the coarse/derived distinction survives into the database instead of flattening into a generic sense.

A node's `file`/`start_byte`/`end_byte` is a **container extent**, not the bytes contributing to its own text. A `Sense` containing a `SubLemma` spans the sub-lemma too; containment is what the interval structure expresses, and exclusive ownership is not implied.

Direct content lives in `content_segments`: the ordered inline pieces of a node's definition, a rubrique's prose, or a citation's quotation, each with its own raw span, `kind` in `text | cross_reference | emphasis`, plus target, source element, editorial origin, and language. This is where the structure the resolver recovered stays queryable rather than being flattened to a string — a cross-reference keeps its resolved target, a source wrapper keeps which element it was. `resolved_entry` holds a raw anchor of whatever kind the reference named: an entry, a variante node, or a rubrique where the reference carried a fragment such as `tache#etymologie`. A span inherited from XMLittré `<exemple>` additionally carries `editorial_origin = 'gannaz'`: this records that the example boundary is an upstream editorial judgment, without converting it into a Deep-Littré adjudication verdict. Other source wrappers leave that column null. The flat text column beside each owner is for reading and search.

Nodes, rubriques and citations are keyed by raw anchor rather than by a minted identifier, so a rebuild over unchanged source produces the same keys and every foreign key into them. A node is not keyed by the identifier of the verdict that asserted it either: re-authoring a verdict over unchanged material would otherwise rename the node it produced. `resolve` rejects a corpus in which two nodes share an anchor, since both renderers assume they do not.

Rubrique containment is retained even where Lex-0 cannot express the enclosing source element directly. A rubrique nested in another rubrique is serialized at the same TEI level required by the content model, but its output is interleaved with the parent by raw source position rather than promoted out of sequence. SQLite records the relationship explicitly in `rubriques.parent_rubrique_id`; `position` is source order within the entry, not census discovery order.

## Parity

Tests assert semantic parity rather than matching XML and SQL implementation details: node types and containment agree, every `<usg>`/`<gram>` fact has the same axis, norm, and target in both, citation counts and resolved authors agree, and no renderer invents a fact absent from the resolved model. Any inline fact present in TEI and absent from `content_segments` is a parity failure, not a serialization difference.

Cross-references are the one place the two outputs are expected to differ, and the asymmetry runs the other way. A reference resolving to an entry or a variante is represented in both with the same target. A reference resolving to a rubrique is recorded in `content_segments.resolved_entry` and emitted in TEI without a target, because the rubrique boundary is not expressed in TEI at all — a rubrique's citations are lifted to entry level while its prose stays in a note, so there is no element for `@target` to name. See [`docs/known-limitations.md`](../../docs/known-limitations.md).

Schema validation is an additional TEI gate, not a substitute for those invariants.
