# TEI Lex-0 serialization contract

Status: **normative for v0.3 serialization**.

Target: **TEI Lex-0 v0.9.5 (2026-02-08), pinned in the repository**.

This document replaces the July compliance worklog as the current project specification. The July research remains useful provenance, but several recommendations drawn from prose chapters or the etymology paper were later overruled by the published RNG. The schema and committed probe verdicts are the arbiter.

The v0.2 release established an important baseline: all 78,599 entries and the whole document validate against the pinned RNG. v0.3 may change semantic structure, but it must preserve that validation gate.

## Authority and method

For a disputed construct:

1. add or consult a minimal case in the Lex-0 probe corpus;
2. validate it against the pinned RNG with `jing`;
3. treat the verdict as authoritative for this project;
4. update this document and the worked examples if the verdict changes a prior interpretation.

Do not infer conformance from TEI P5, the Lex-0 prose alone, or Bowers et al. when the pinned RNG says otherwise.

Two July-era corrections are already settled:

- `<dictScrap>` is admitted nowhere relevant by the pinned RNG and must not be emitted;
- direct `<date>` inside `<etym>` is rejected by the pinned RNG, so historical century metadata uses the validated project pattern described below.

## Document shell

The document root is:

```xml
<TEI xmlns="http://www.tei-c.org/ns/1.0" xml:id="littre" type="lex-0">
```

The header contains:

- `fileDesc/titleStmt` with full and abbreviated titles;
- `editionStmt` for the TEI Lex-0 edition statement;
- `publicationStmt` with explicit availability/licence;
- `sourceDesc/listBibl type="dictionaries"` with structured records for Littré and XMLittré;
- `profileDesc/langUsage`;
- `revisionDesc`.

The object language is `fr-x-lit19c`; the working language is `fr`.

The current validated header pattern is:

```xml
<profileDesc>
  <langUsage>
    <language ident="fr-x-lit19c" role="objectLanguage">
      <name xml:lang="en">19th-century literary French</name>
      <name xml:lang="fr">Français littéraire du XIXᵉ siècle</name>
      <date notBefore="1801" notAfter="1900"/>
    </language>
    <language ident="fr" role="workingLanguage">
      <name xml:lang="en">French</name>
      <name xml:lang="fr">Français</name>
    </language>
  </langUsage>
</profileDesc>
```

## Entries and senses

Every `<entry>`, top-level or nested, carries both `xml:id` and `xml:lang`.

Top-level dictionary entries use:

```xml
<entry xml:id="..." xml:lang="fr-x-lit19c" type="mainEntry">
```

Form-bearing semantic substructures use the Lex-0 recursive-entry mechanism. In v0.3:

- `SubLemma` normally serializes as `type="relatedEntry"`;
- a form-bearing `VoiceVariant` may serialize as `type="homonymicEntry"` where the resolved structure warrants an entry-like grammatical variant.

Every emitted `<sense>` carries `xml:id`.

The renderer may emit a coarse `<sense><def>…</def></sense>` for material whose finer semantic structure remains unadjudicated. That is a serialization fallback, not a workflow annotation.

`ana="unclassified"` is not emitted in v0.3.

## Forms

Every `<form>` carries a `type` accepted by the pinned schema.

Entry lemmas preserve the printed form directly:

```xml
<form type="lemma">
  <orth>PRINTED FORM</orth>
</form>
```

The renderer does not add a casing-normalization claim merely because it can normalize a headword internally. Editorially reconstructed/read forms use the separate `@value` convention below.

Where a form is editorially extracted rather than printed as a standalone lemma, use the validated condensed-lemma pattern with `@value` rather than pretending that the source printed a separate orthographic token:

```xml
<form type="lemma">
  <orth value="tenir cabinet"/>
</form>
```

A form-bearing semantic node may carry several forms. The first is emitted as `form type="lemma"` and additional alternatives as sibling `form type="variant"`; `variant` is admitted by the pinned Lex-0 schema. If several editorial readings share one printed source span, each reading uses the condensed `<orth value="…"/>` shape rather than duplicating the coordinated source wording as element text.

Inflectional variants may be nested forms when the schema admits the required structure. Any other use of less common `form/@type` values must be represented in the probe before becoming project policy.

## Grammatical information

Entry-level grammar is a direct child of `<entry>`, not a child of the lemma `<form>`:

```xml
<gramGrp>
  <gram type="pos" norm="noun">s.</gram>
  <gram type="gender" norm="feminine">f.</gram>
</gramGrp>
```

Compound Littré labels are decomposed into typed grammatical atoms where the calibrated routing tables support them.

Grammatical information is not encoded as `<usg type="gram">` in released TEI.

Grammatical facts attached to a particular sense or form are placed on that target rather than promoted to the whole entry.

## Usage qualifications

`<usg>` uses the Lex-0 closed typology accepted by the pinned RNG:

- `temporal`;
- `geographic`;
- `domain`;
- `frequency`;
- `textType`;
- `attitude`;
- `socioCultural`;
- `meaningType`;
- `normativity`;
- `hint`.

`register` is not a Lex-0 type and is never emitted.

Examples:

```xml
<usg type="socioCultural" norm="familiar">familièrement.</usg>
<usg type="meaningType" norm="figurative">fig.</usg>
<usg type="domain" norm="botany">terme de botanique.</usg>
<usg type="meaningType" norm="proverbial">prov.</usg>
```

Compound printed labels may yield more than one `<usg>` element, including elements of different types. This follows the v0.3 semantic model: qualifications are orthogonal facts, not one source-side "register" value.

`hint` is the honest fallback for usage information that has been examined but has no supported typed home. It is not a replacement for unexamined adjudication state.

## Sub-lemmas and multiword units

`<re>` is not part of the target representation. A multiword unit with its own form/gloss structure is represented recursively as a nested entry inside the sense to which it belongs:

```xml
<sense xml:id="...">
  <def>...</def>
  <entry xml:id="..." xml:lang="fr-x-lit19c" type="relatedEntry">
    <form type="lemma"><orth value="tenir cabinet"/></form>
    <sense xml:id="...">
      <def>tenir conseil.</def>
    </sense>
  </entry>
</sense>
```

The decision that a span is a `SubLemma` comes from adjudication, not punctuation or an XMLittré locution tag alone.

Punctuation between a nested entry's form and its gloss is recovered from the source and emitted as `<pc>` between `<form>` and `<sense>`, so `Tenir cabinet, tenir conseil.` round-trips as `<orth>Tenir cabinet</orth><pc>,</pc>…<def>tenir conseil.</def>`. The punctuation belongs to neither constituent and is not silently dropped.

A source block may simultaneously yield a sub-lemma and one or more usage qualifications. The `<usg>` elements are attached to the semantic target established by the adjudication record; they do not compete with the sub-lemma for a single block classification.

A proverb is not a separate usage axis. Where proverbial status is applicable, it is `meaningType=proverbial`, attached to the sense or sub-lemma it qualifies.

## Definitions and examples

`<def>` contains definitional prose, not workflow labels or example material that has been positively identified as a citation/example.

Source `<mentioned>` material requires semantic handling:

- a redundant copy of an already represented form/example may be omitted;
- a novel example established by adjudication becomes `<cit type="example"><quote>…</quote></cit>`;
- a phrase wrapper that merely preserves print emphasis may flatten to schema-valid `<hi rend="italic">` in contexts where the original source wrapper has no Lex-0 counterpart.

The v0.3 renderer does not run heuristics over definition punctuation to invent this structure. It serializes resolved facts and otherwise preserves coarse prose.

A `<def>` is never punctuation alone. Littré prints a full stop after a label that XMLittré encloses without it — `<nature>Absolument</nature>.` — and once the surrounding material is claimed by markers and asserted nodes, that stop is all the definition content left. It is source-visible and is kept, but as `<pc>.</pc>` following the `<gramGrp>` or `<usg>`, not as `<def>.</def>`; a `<def>` asserts a definition that is not there. `<pc>` is schema-valid directly inside `<sense>`. The same rule covers any punctuation-only remainder, whatever the mark.

Two uses of `<pc>` therefore occur inside a sense: separating a nested entry's form from its gloss, and carrying terminal punctuation of a label. Nothing in the markup distinguishes them; both are punctuation the source prints and no element owns.

## Citations

Synchronic examples use the validated form:

```xml
<cit type="example">
  <quote>...</quote>
  <bibl>...</bibl>
</cit>
```

The pinned schema has a closed `cit/@type` vocabulary. Do not use bare `<cit>` merely because an external etymology example does so if the probe rejects it.

Littré's citation anaphors are resolved over the entry in **source** order — the semantic tree is
built later and may reattach citations by containment, which would otherwise reorder them. The
printed surface is never replaced. A resolved author therefore remains `<author corresp="#…">ID.</author>` in
text, with `@corresp` pointing to the immediately preceding citation; an anaphoric `ib.` remains the
printed `<biblScope>` text with the same kind of link. Every synchronic citation receives an
`xml:id` so these links survive semantic reattachment.

SQLite additionally carries the resolved author value for `ID.` because that value is established
without bibliographic inference. It does not synthesize a resolved string for `ib.`: forms such as
`ib. III` can retain the preceding work while changing the locus, so the durable fact is the
antecedent citation rather than a guessed normalized reference. An `ID.` or `ib.` with no preceding
citation produces an `author_unresolved` or `reference_unresolved` review finding respectively.

`@ana` carries epistemic provenance only. Anaphora resolution is a processing relation, not an
epistemic classification, so it is not encoded there.

Bibliographic normalization beyond what can be established safely from Littré remains incremental; missing `biblScope/@unit` is not repaired by guessing.

## Cross-references

Lexical cross-references use `<xr>/<ref>` with the required types:

```xml
<xr type="related">
  <lbl>voy.</lbl>
  <ref type="entry" target="#agame">AGAME</ref>
</xr>
```

`xr/@type` uses the closed relation vocabulary admitted by the pinned schema. `ref/@type` identifies the kind of lexical target.

An internal `target="#xml-id"` is emitted only when the target is reliably resolved. A conformant textual reference is preferable to a guessed pointer.

Cross-references are relations in the v0.3 semantic model, not usage qualifications.

## Rubriques and notes

`RubriqueKind` remains source/structural vocabulary. Serialization depends on the rubrique's semantic role and the pinned content model.

### Etymology and historique

`<etym>` carries the etymological account of the `ÉTYMOLOGIE` rubrique and nothing else. Historical
attestations are **not** folded into it; `HISTORIQUE` serializes at entry level, structurally
parallel to `<etym>` rather than subordinate to it. See *Rubriques do not fold into `<etym>`* below
for the encoding and the reasoning.

Two July-era recommendations remain superseded here:

- direct `<date>` inside `<etym>` is not used, because the pinned RNG rejects it;
- historical citations retain a schema-admitted `type="example"`; the diachronic distinction is
  carried by `cit/@subtype`, not by `@ana`, which v0.3 reserves for epistemic provenance.

### Remarques and other notes

`<dictScrap>` is not emitted. The pinned RNG rejects it in the probed contexts.

When a note cannot contain a citation directly in the desired location, the renderer uses a schema-valid sibling/containing structure established by the probe rather than inserting `<dictScrap>` as an escape hatch. The v0.2 validated emitter places rubrique citations as allowed siblings after note content where necessary.

### Supplément

Supplement provenance remains explicit. Supplement material may stay in a `<note type="supplément">` or other schema-valid structure until a richer adjudication is justified. The rewrite must preserve the fact that the material originates in the Supplement rather than silently folding all addenda into the base article.

## Etymology

The etymology subsystem is retained conceptually because it already models orthogonal events/segments independently of `IndentRole`.

Validated building blocks include:

```xml
<cit type="etymon" xml:lang="la">
  <lang expand="latin" norm="la">lat.</lang>
  <form><orth>truncare</orth></form>
</cit>
```

and:

```xml
<cit type="cognate" xml:lang="oc">
  <lang expand="provençal" norm="oc">Provenç.</lang>
  <form><orth>troncar</orth></form>
</cit>
```

Unmarked etymological connectors such as `et`, `de`, and `ou` remain ordinary source text; the renderer does not promote them to `<lbl>` merely from position. Explicit labels and etymological cross-references use their dedicated schema-valid structures, with cross-references following the same `<xr>/<ref>` contract as elsewhere.

Compound constituents are not cognates. A source form identified deterministically as a constituent is rendered with Lex-0's standard `<cit type="etymon"><form><orth>…</orth></form></cit>` pattern; for an unlabelled French constituent, `xml:lang="fr"` is supplied. The resolver may retain the internal constituent distinction, but the TEI does not invent a `component` value where the Lex-0 etymon vocabulary already expresses the derivational relation. The detector is intentionally conservative: it only promotes a leading coordinated run of italic form events when at least two forms occur in headword order.

Source typography in etymologies is retained explicitly rather than treated as implicit in `<orth>`. A form originating in XMLittré `<i>` therefore emits `<orth rend="italic">…</orth>`, whether it is an etymon or a cognate. This preserves the reliable italic/roman distinction observed in Littré's etymologies while keeping all lexical forms in the same `<cit>/<form>/<orth>` structure. Source capitalization is preserved; structural rendering does not silently normalize sentence-initial `À` to `à`.

Punctuation that separates recognized etymology events remains visible in source order rather than being discarded or hoisted. Punctuation-only source gaps are emitted as `<pc>`; punctuation belonging inside a language/cognate unit is emitted as `<pc>` there. Etymology paragraphs are ordered as source units and their segment order is preserved internally, preventing unanchored connectors or punctuation from floating ahead of precisely anchored forms.

Regional language labels use the committed language table just like language abbreviations. `Berry` routes to the existing Berrichon private-use code `fr-x-berrich`, so a following cognate carries `xml:lang="fr-x-berrich"` and the printed `Berry` remains in `<lang>`.

A reconstructed/uncertain marker such as Littré's *fictif* may use the established fallback:

```xml
<usg type="hint">fictif</usg>
```

Unresolved suspicious tokens are preserved rather than silently corrected, for example:

```xml
<lbl ana="suspect">re</lbl>
```

The project may mirror these residues in the adjudication/review database, but the visible token remains in the corpus.

In v0.3 the segmenter is deterministic enrichment, not adjudication. It is reconstructed every
build from source plus the committed `etym_language_table.toml`, and a suspect token becomes a
generated `etymology_suspect` review finding rather than a stored judgment. Segments whose position
is known — form events and anchors — carry a raw anchor; connectors and prose are located by their
containing rubrique block. Anchoring granularity follows adjudication need, so if an etymological
fact later requires a durable judgment, it acquires its own span at that point.

### Unsegmented etymologies are counted, not marked

Segmentation keys on Gannaz's italic and anchor markup, and that markup is uneven: an etymology
carrying neither is often the same string a marked one would be, so it falls back to a single prose
segment. The fallback emits an `etymology_unsegmented` review finding anchored to the containing
block, with detail `no_events` when the paragraph carried no recognized markup and
`unrecognized_markup` when markup outside the event inventory could have been severed across
segments. That count is the denominator classification coverage is reported against.

The finding is the whole of the record. It is not marked in the TEI and not mirrored in the
`etymology` table, because it states where this parser stopped rather than anything about Littré or
Gannaz — `ana="suspect"` is a claim about a token in the text, `unsegmented` would be workflow
state, and the published edition carries the first and not the second.

### Rubriques do not fold into `<etym>`

v0.2 folded `HISTORIQUE` into `<etym>` with century markers and `ana="attestation"` citations. v0.3
does not fold, on fidelity grounds. The v0.2 shape was never legal anyway — `<date>` may not sit
beside `<cit>` inside `<etym>` — and the recorded fold decision is superseded.

The enabling fact, verified against v0.9.5: `model.entryPart.top` admits `cit` and `lbl` directly,
so entry content is `bibl, biblStruct, cit, entry, etym, figure, form, gramGrp, lbl, listBibl,
metamark, note, num, pc, ref, sense, usg, xr`. A rubrique's citations therefore live at entry
level, structurally parallel to `<etym>` rather than subordinate to it.

This is not a refinement. `<note>` cannot hold `<cit>` — its content is phrase-level only — so the
previous `<note type="historical"><seg>` rendering silently destroyed every rubrique citation:
261 of the development corpus's 818 citations, with their authors and references, reached neither
output. The no-fold encoding recovers all of them.

Encoding:

- citations are lifted to entry level as `<cit type="example" subtype="…">`, because `cit/@type` is
  a closed list with no `attestation` value;
- a century header becomes `<lbl type="dateRange">`, printed once over the group it introduces, as
  the source prints it. HISTORIQUE's `Ajoutez :` lead marker becomes a separate
  `<lbl type="supplement">`; either marker may precede the other, and any remaining lead text stays
  prose. `<date>` cannot sit at entry level, so the machine-readable range is
  additionally written into each attestation's `<bibl>` as
  `<date notBefore="1501" notAfter="1600">XVIe s.</date>`. This repeats per citation what Littré
  prints once, and is emitted anyway: without it the century survives only as prose and neither
  output is queryable by date. Years are `xsd:gYear`, so a tenth-century range is `0901`, not
  `901`. The resolver computes the range and carries it to the citations the header introduces;
  neither renderer infers it;
- remaining prose stays in `<note type="…">`, since `<seg>` is **not** legal at entry level;
- rubriques render in **source order**. Entry content is unordered, and Littré puts `HISTORIQUE`
  before `ÉTYMOLOGIE` in some entries and after in others.

A `<gramGrp>` at entry level carries only the labels that qualify the headword. Where the source
announces a second headword form before a second label — printed in capitals in 79 entries,
`ACCORDÉ … ACCORDÉE (a-kordée) s. f.`, or given its own `<prononciation>` in 4 — the label belongs
to that form, and attaching it to the entry made the entry both masculine and feminine. Those
labels go to the header note with the form they qualify, until a pass can lift the pair into a
`<form>` of its own. Prose between two labels does not demote the second: TARGUER prints its
conjugation between `v. a.` and `v. réfl.` and both stay in the `<gramGrp>`.

`note/@type="header"` carries the entete material that is neither the pronunciation nor a
part-of-speech label — 3,034 entries have some, and it is heterogeneous enough that any type naming
the content would be a classification the source does not state. The type names its position
instead: one note per contiguous run, in source order, after `<gramGrp>`, mirroring where Littré
prints it. `<note>` is available at entry level via `model.global`. A later pass can lift a header
note into `<form type="inflected">`, an extended `<gram>`, or a typed note without a schema change.

`lbl/@type` and `cit/@subtype` are unconstrained by the schema, so their values are project
convention. Citation/note conventions are committed in `rubrique_conventions`; label types are the
committed `dateRange` and `supplement`. Proverb material uses the singular token `proverb` both as
`note/@type` and `cit/@subtype`.

A `PROVERBE` or `PROVERBES` rubrique additionally preserves the printed heading, `Proverbe.` or
`Proverbes.`. A direct `<lbl>` would be preferable in the abstract, but the pinned Lex-0 schema does
not admit `<lbl>` inside `<sense>`, and proverb rubriques can occur there. When coarse proverb prose
is the first rubrique content, the heading and prose therefore share one note:
`<note type="proverb" xml:id="…"><seg type="label">Proverbe.</seg> …</note>`. This avoids a
second indistinguishable proverb note and removes the generic outer `<seg>` formerly wrapped around
the note content. Where no coarse prose note is available to carry the heading, the fallback remains
a distinct `<note type="proverb" subtype="label">Proverbe.</note>`.

Where a coarse proverb contains prose plus lifted attestations, the content note receives an
`xml:id` and each following proverb citation points back to that note with `@corresp`. This retains
the relationship even though Lex-0 forbids `<cit>` inside `<note>`. Citation-only proverb material
is left unlinked rather than given an invented target. For rubriques other than proverbs, the
rubrique boundary is not expressed in TEI; the `subtype` distinguishes the kind, and SQLite retains
`origin`, `rubrique`, and the raw anchor, so the grouping stays fully recoverable.

Two further findings from the same validation pass: `<dictScrap>` does not exist in Lex-0 v0.9.5,
so the `remarque`-via-`dictScrap` plan is unimplementable and remarque citations take the same
entry-level treatment; and the etymon-internal `<gloss>` accepts no attributes, so
`<gloss xml:lang="fr">` is rejected and W4's specification of it is wrong. `<biblScope>` is valid
alongside `<citedRange>`.

## Phrase-level source wrappers

XMLittré source wrappers such as `<exemple>`, `<mentioned>`, `<foreign>`, and verbatim italic `<i>` are not assumed to be legal in every Lex-0 content model.

Where a wrapper represents only print emphasis and the richer source element is disallowed, v0.2 established a validated fallback to `<hi rend="italic">`, preserving `xml:lang` when available. Nested `<hi>` must respect the pinned content model; flatten redundant nesting rather than generating invalid markup.

`<exemple>` is not such a wrapper. Comparison with the print shows that its contents are roman text and that the element records an XMLittré editorial judgment rather than typographic emphasis. Coarse output therefore preserves the inherited span as `<seg type="example">…</seg>` without `<hi>`. This explicitly supersedes the earlier v0.3 decision that rendered `<exemple>` as `<seg type="example"><hi rend="italic">…</hi></seg>`.

Semantic structures such as etymons or examples should be represented by their dedicated Lex-0 elements when adjudication has established them, not merely by italic presentation.

## Pronunciation

A true pronunciation remains `<pron>` inside the lemma form.

Littré also places prescriptive or explanatory prose in the source pronunciation field. Such prose may serialize as `<note type="pronunciation">` when positively identified. The v0.3 architecture should move the decision out of renderer heuristics and into an explicit adjudication/property path; uncertain material stays coarse rather than being reclassified from stylistic cues alone.

## Workflow and provenance annotations

Published TEI expresses claims about the dictionary, not pipeline progress.

Therefore:

- no `ana="unclassified"`;
- no role names from the old classifier;
- no heuristic confidence bucket merely because a pass has not run.

Project annotations that express a corpus fact or editorial epistemic claim may remain where the schema admits them, including:

- `ana="suspect"` for explicitly preserved unresolved source tokens.

`@ana` carries epistemic provenance only, and its permitted values are whitelisted by test so a new
one must be consciously admitted. The diachronic distinction that v0.2 expressed as
`ana="attestation"` is now `cit/@subtype="attestation"`.

Pass version, decision procedure, and unresolved verdict state live in the authoritative adjudication records. Coverage is computed against the current census/pass definitions and mirrored into SQLite; none of this workflow state is serialized as TEI semantics.

## Identifier policy

Every released entry and sense receives the `xml:id` required by the pinned schema.

Sense identifiers are positional: `angoisse_s3` is the third sense of the entry, `angoisse_s3.2`
the second sense inside it. Dots are legal, since `xml:id` is an `xsd:ID` and therefore an NCName.
Every sense is numbered, including an only child. Uniqueness is guarded separately, for the cases
where two entries normalize to the same headword slug, so the ordinal always means position.

Only source blocks take a positional slot. A `SubLemma` or `VoiceVariant` is named from its form (`angoisse_avaler_des_poires_d_angoisse`) and is not counted among its siblings, so asserting one inside a block does not renumber the source senses that follow it. A sense id is therefore stable under adjudication: verdicts landing over the course of a campaign leave every existing positional id naming the same source material.

The ids are not stable under source change. A patch or upstream revision that adds or removes a block renumbers the blocks after it. v0.3 does not promise stability across pre-1.0 releases on that axis; a frozen identifier registry would be needed, and none is planned before 1.0.

Internal adjudication validity uses the canonical classification surface plus projected selections; the stored raw block span is only a locator. Opaque record/node ids identify authored objects without coupling them to positional TEI ids.

## Validation gates

A release is blocked unless:

- the full document validates against the pinned RNG;
- every entry validates in the per-entry harness;
- the committed probe produces its expected verdicts;
- no new schema workaround is introduced without a probe case;
- TEI/SQLite semantic parity tests pass.

The schema-valid v0.2 output remains a preservation oracle, but byte-for-byte or tree-for-tree equality is not expected from the v0.3 semantic rewrite.
