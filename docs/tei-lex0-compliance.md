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

Entry lemmas use:

```xml
<form type="lemma">
  <orth norm="...">PRINTED FORM</orth>
</form>
```

Printed casing is preserved in element text; normalized casing may be stored in `@norm`.

Where a form is editorially extracted rather than printed as a standalone lemma, use the validated condensed-lemma pattern with `@value` rather than pretending that the source printed a separate orthographic token:

```xml
<form type="lemma">
  <orth value="tenir cabinet"/>
</form>
```

Inflectional variants may be nested forms when the schema admits the required structure. Any use of less common `form/@type` values must be represented in the probe before becoming project policy.

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

A source block may simultaneously yield a sub-lemma and one or more usage qualifications. The `<usg>` elements are attached to the semantic target established by the adjudication record; they do not compete with the sub-lemma for a single block classification.

A proverb is not a separate usage axis. Where proverbial status is applicable, it is `meaningType=proverbial`, attached to the sense or sub-lemma it qualifies.

## Definitions and examples

`<def>` contains definitional prose, not workflow labels or example material that has been positively identified as a citation/example.

Source `<mentioned>` material requires semantic handling:

- a redundant copy of an already represented form/example may be omitted;
- a novel example established by adjudication becomes `<cit type="example"><quote>…</quote></cit>`;
- a phrase wrapper that merely preserves print emphasis may flatten to schema-valid `<hi rend="italic">` in contexts where the original source wrapper has no Lex-0 counterpart.

The v0.3 renderer does not run heuristics over definition punctuation to invent this structure. It serializes resolved facts and otherwise preserves coarse prose.

## Citations

Synchronic examples use the validated form:

```xml
<cit type="example">
  <quote>...</quote>
  <bibl>...</bibl>
</cit>
```

The pinned schema has a closed `cit/@type` vocabulary. Do not use bare `<cit>` merely because an external etymology example does so if the probe rejects it.

Resolved author information may be represented in `<author>` while retaining the printed abbreviation/provenance required by the data model.

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

Historical attestations are folded into the entry's `<etym>` after the etymological account.

The validated v0.2/v0.3 project pattern is:

```xml
<etym>
  ...etymological account...
  <lbl>XVIe s.</lbl>
  <cit type="example" ana="attestation">
    <quote>...</quote>
    <bibl>
      ...
      <date notBefore="1501" notAfter="1600">XVIe s.</date>
    </bibl>
  </cit>
</etym>
```

This pattern deliberately differs from the July recommendation based on Bowers et al.:

- direct `<date>` inside `<etym>` is not used because the pinned RNG rejects it;
- historical citations retain a schema-admitted `type="example"` and use `ana="attestation"` to distinguish diachronic attestations from synchronic examples;
- the century's human-readable marker is `<lbl>`;
- the machine-readable date range is duplicated into each attestation's `<bibl>`.

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

Connective text may use `<lbl>` or schema-valid prose/segment structures. Etymological cross-references use the same `<xr>/<ref>` contract as elsewhere.

A reconstructed/uncertain marker such as Littré's *fictif* may use the established fallback:

```xml
<usg type="hint">fictif</usg>
```

Unresolved suspicious tokens are preserved rather than silently corrected, for example:

```xml
<lbl ana="suspect">re</lbl>
```

The project may mirror these residues in the adjudication/review database, but the visible token remains in the corpus.

## Phrase-level source wrappers

XMLittré source wrappers such as `<mentioned>`, `<foreign>`, and verbatim italic `<i>` are not assumed to be legal in every Lex-0 content model.

Where a wrapper represents only print emphasis and the richer source element is disallowed, v0.2 established a validated fallback to `<hi rend="italic">`, preserving `xml:lang` when available. Nested `<hi>` must respect the pinned content model; flatten redundant nesting rather than generating invalid markup.

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

- `ana="attestation"` for historical citations;
- `ana="suspect"` for explicitly preserved unresolved source tokens.

Coverage, method, adjudicator, pass version, and unresolved workflow state live in the authoritative adjudication store and its SQLite mirror.

## Identifier policy

Every released entry and sense receives the `xml:id` required by the pinned schema.

These ids are rendering identifiers. v0.3 does not promise stability across pre-1.0 releases while structural adjudication is still splitting and regrouping material.

Internal adjudication identity uses source anchors and opaque record/node ids instead.

## Validation gates

A release is blocked unless:

- the full document validates against the pinned RNG;
- every entry validates in the per-entry harness;
- the committed probe produces its expected verdicts;
- no new schema workaround is introduced without a probe case;
- TEI/SQLite semantic parity tests pass.

The schema-valid v0.2 output remains a preservation oracle, but byte-for-byte or tree-for-tree equality is not expected from the v0.3 semantic rewrite.
