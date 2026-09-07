# Overview

Read this before the other architecture documents. It introduces the vocabulary the rest of them use, by following one entry from the source file to the published output.

The entry is ANGOISSE. It's in the development corpus at `test/corpus/source/a.xml`, and the adjudication records quoted below are the ones committed at `test/corpus/adjudication`, so everything here can be checked against the repository.

## The source

XMLittré gives each dictionary entry an `<entree>` with two parts: an `<entete>` carrying the pronunciation and the grammatical label, and a `<corps>` carrying the senses.

```xml
<entree terme="ANGOISSE">
<entete>
	<prononciation>an-goi-s', et non an-goi-z'</prononciation>
	<nature>s. f.</nature>
</entete>
<corps>
<variante num="1">Sentiment de resserrement à la région épigastrique, ...</variante>
```

Senses are `<variante>` elements. Within a sense, further material is set off in `<indent>` elements. Named sections at the end of the entry are `<rubrique>` elements, each with a `@nom`. ANGOISSE carries three rubriques: the history of the word (HISTORIQUE), its etymology (ÉTYMOLOGIE), and additions from Littré's 1877 supplement (SUPPLÉMENT AU DICTIONNAIRE).

The third sense is where the interesting problem lives:

```xml
<variante num="3">Poire d'angoisse, poire d'un goût très âpre.
<indent><semantique type="indicateur">Familièrement.</semantique> Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs. 
<cit aut="MOL." ref="Escarb. 15">Je vous présente des poires de bon-chrétien pour des poires d'angoisse que vos cruautés me font avaler tous les jours</cit>
</indent>
<indent>Poire d'angoisse, espèce de bâillon en fer dont se servaient les voleurs pour étouffer les cris.
</indent>
</variante>
```

## Blocks and the census

A *block* is a stretch of source that a semantic judgment can be made about. The `<variante>` above is a block, and so is each of the two `<indent>` elements inside it. Blocks nest: the two indents sit inside the variante, and the census records them in that relationship.

Not every element is a block. The `<cit>` is a quotation, handled deterministically as a citation. The `<prononciation>` is form data with its own path through the pipeline. The `<nature>` in the entete is a block of its own kind, since a grammatical label is something a judgment might be made about.

The *census* enumerates every block in the corpus, walking the source's XML tree. It runs before any semantic work and depends on nothing semantic. Its purpose is to fix a denominator: when a pass later reports that it has examined a certain number of blocks, the population that number is measured against is a stable property of the source.

Each block gets a *kind*, decided by what contains it rather than by its element name. An `<indent>` inside a `<résumé>` is a different kind from an ordinary `<indent>`, because résumé material summarizes senses that appear elsewhere in the entry. There are nine kinds; `src/Census/README.md` lists them and gives the reasoning for each.

## Two kinds of fact

Look again at the first indent. Three separate things are true of it.

*Familièrement.* is a register label. Littré printed it, and Gannaz tagged it in XMLittré as `<semantique type="indicateur">`, so its exact boundaries are given by the source.

*Avaler des poires d'angoisse* is a multi-word unit, something closer to a headword than to a definition.

*subir des mortifications, de vifs déplaisirs* defines that expression. It does not define *angoisse*.

The first of those is explicit in XMLittré: an element with a name and a span. The second and third are not marked in any way. They sit in the text as ordinary prose, looking exactly like the definition in the sibling indent below them, which really is a plain definition of *poire d'angoisse*.

This division runs through the whole system. Facts that XMLittré states explicitly are reconstructed from the source on every build, deterministically, by code and committed normalization tables. Facts that require reading the text, on the other hand, are *adjudicated*.

## Adjudication

An adjudication is a recorded judgment about source material that XMLittré does not mark. Judgments are made one question at a time, and each question is a *pass*.

A pass declares, in code, its name and version, the population of blocks it applies to, and the question it asks. Three passes bear on the ANGOISSE indent:

`sublemma` asks whether the block contains a separately form-bearing lexical unit: an expression presented as its own thing, with its own gloss.

`voice_variant` asks whether the block introduces a pronominal or reflexive alternant of the headword that governs its own sense material.

`qualification_scope` asks whether an explicit marker in the block governs something narrower than the block containing it.

Each pass answers with one of four outcomes for a given block: *positive*, the class applies; *negative*, it does not; *unresolved*, examined without reaching a decision; or no record at all, meaning the block has not been examined. The absence of a record is inconclusive.

Asking one question at a time keeps the passes independent. A `sublemma` verdict on this block does not disturb the `qualification_scope` verdict, and adding a new pass later does not invalidate the records already made.

## The projection and the surface

A judgment has to refer to a piece of text. Referring to it by raw byte offsets in the file could accidentally tie the judgment to an irrelevant bit of XML. For example, a later patch inserting markup elsewhere in the file would move every offset after it.

So a block is *projected* before it is presented for judgment. The `block_text` projection takes the block, removes its descendant blocks and its citations, strips markup, decodes character references, and collapses whitespace, keeping a mapping back to source positions. For the ANGOISSE indent the projection is:

```text
Familièrement. Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.
```

Judgments select substrings of that text and are stored as byte intervals in it.

Alongside the projected text, the block is given a *classification surface*: the block's kind, its projected text, the explicit markers found in it, and the citation context supplied with it. This is exactly the material a classifier is shown, serialized deterministically and hashed once as `surface_sha256`. The hash is what tells a later build whether a stored judgment still describes the material it was made about. If the surface is identical, the judgment stands and its projected intervals are mapped onto current source positions. If the surface changed, the judgment is stale, and a development build reports and skips it while a release build refuses it.

The block's raw span is stored too, as a locator to find it again quickly. The hash decides whether the judgment applies.

## The records

Here is the committed `sublemma` verdict on this block, abbreviated:

```json
{
  "pass": "sublemma", "pass_version": 1,
  "source": {"file": "a.xml", "start_byte": 645, "end_byte": 959},
  "surface_sha256": "cacb6b11de4aa8f0...",
  "outcome": "positive",
  "assertions": [{
    "node_type": "SubLemma",
    "span": {"start_byte": 17, "end_byte": 93},
    "constituents": [
      {"name": "form",  "span": {"start_byte": 17, "end_byte": 45}},
      {"name": "gloss", "span": {"start_byte": 47, "end_byte": 93}}
    ]}],
  "residuals": [{"start_byte": 1, "end_byte": 16}]
}
```

Every interval in `assertions` and `residuals` indexes the projected text above. Bytes 17 through 45 are *Avaler des poires d'angoisse*; 47 through 93 are *subir des mortifications, de vifs déplaisirs.*; bytes 1 through 16 (the register label) are residual.

A *semantic node* is what a positive structural verdict asserts: a span of the entry that the model treats as a unit. This one is a `SubLemma`, which is *form-bearing*, meaning it carries a printed form of its own that the output can present the way it presents a headword. The named intervals inside it are *constituents*, the form and its gloss.

The two constituents are not adjacent. Bytes 45 and 46 are the comma and space that Littré printed between them, belonging to neither. That material is kept as the node's *separator*, which is why a comma is not silently attached to the end of a form.

The residual matters for a different reason. A positive structural verdict is *exhaustive*: the asserted node spans plus the residual spans must account for the whole projected text. Here, node 17–93 plus residual 1–16 covers everything, so the verdict is a complete statement about the block rather than a note about one part of it.

The `voice_variant` verdict on the same block is negative — no pronominal alternant is present — and carries no assertions. Its record notes: *no pronominal alternant; the multiword unit is a sub-lemma*.

The `qualification_scope` verdict is positive, and asserts one scope:

```json
"scopes": [{"marker": {"start_byte": 1, "end_byte": 16},
            "target": {"start_byte": 17, "end_byte": 93}}]
```

The marker is *Familièrement.* and its target is the sub-lemma. The default for a marker is that it governs the innermost resolved node containing it, which here would be the whole indent. This record says it governs the expression specifically.

Note what the scope record does not contain. It says which text the marker covers, and nothing about what the marker means. Turning *Familièrement.* into `type="socioCultural" norm="familiar"` is done by the committed normalization tables in `data/`, on every build, from the printed text.

## A second block: DISPENSER

The ANGOISSE indent shows one of the two structural alternatives asserted and the other denied. Seeing the other one asserted takes a second block. `DISPENSER` variante 7, at `d.xml` bytes 4732–4868, is:

```xml
<variante num="7">Se dispenser, <nature>v. réfl.</nature> Être départi. Les honneurs se dispensent quelquefois au hasard.</variante>
```

projecting to:

```text
Se dispenser, v. réfl. Être départi. Les honneurs se dispensent quelquefois au hasard.
```

Here Littré is opening what amounts to a small entry underneath the verb: a printed pronominal form, *Se dispenser*, with sense material of its own. The `voice_variant` verdict is positive and asserts a `VoiceVariant` over 1–90, the whole projected text, with form 1–13 and gloss 25–90. Its residual list is empty, since the node already accounts for everything.

The `qualification_scope` verdict on this block is negative, and its note gives the reason: *v. réfl. governs the pronominal alternant that contains it*. That is the containment default doing its job. The marker sits at 15–24, inside the asserted node, so the rule that a marker governs the innermost node containing it already puts the grammatical property where it belongs, and there is nothing to record.

The scope pass is easier to understand now when you set these two blocks side by side. On the ANGOISSE indent the default would have assigned *Familièrement.* to the entire block, which is wrong, so a positive record names the narrower target. On this block the default is already right, so the verdict is negative — which is not an absence of information but the statement that every explicit marker here scopes by containment.

Note also that `v. réfl.` is an inline `<nature>`, sitting inside a block rather than in the entry header. The same element in an `<entete>` describes the whole lemma, as in `ÉVADER (S')`, and produces no voice variant at all.

## Qualifications and relations

A *qualification* is a fact contributed by a marker: a register, a domain, a temporal note, a grammatical property. Every qualification names the text it applies to, so it is never merely attached to a block. Usage qualifications and grammatical ones are kept apart, since they occupy different positions in the output.

A *relation* points from one place to another — most often a cross-reference, where Littré writes *voy.* and a headword. Relations are resolved against the corpus so the target is identified before either output is written.

Both are separate from the node axis. A node has at most one type; qualifications and relations accumulate freely on the same material. That separation is what lets the register label and the sub-lemma both be recorded here. Giving the indent a single type would force a choice between them.

## Deriving an ordinary sense

Most blocks are ordinary senses: a definition, perhaps with examples, nothing structurally special. No pass asserts this, because there is nothing positive to observe. An ordinary sense is what a block is when none of the special structures are present, and absence is established only by looking for each thing that could have been there.

So `Sense` is derived. Once every structural pass has examined the block and answered, and the answers are compatible, the block is *closed*, and what the answers did not claim is an ordinary sense. Before that, "no sub-lemma here" and "nobody looked for one" are the same observation, and the pipeline declines to read either one out of silence.

For the ANGOISSE indent, `sublemma` answered positive and `voice_variant` answered negative. Both structural questions have been asked, so the block closes: it resolves as a `Sense` spanning the whole indent, with the sub-lemma nested inside it.

Closure is why the set of structural passes is declared in one place. Adding a fourth alternative immediately means blocks examined by only three no longer close, and stay coarse until the new question has been asked of them. Records already made stay valid.

Where a block has not closed, the pipeline still publishes it, as a sense with a definition and no finer structure. That output carries no claim that anyone examined it.

## The output

Before adjudication, the indent renders coarsely. Everything Littré printed is present, the register label is typed and normalized, and the expression is inside the definition:

```xml
<sense xml:id="angoisse_s3.1">
  <usg type="socioCultural" norm="familiar">familièrement.</usg>
  <def>Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.</def>
</sense>
```

With the three verdicts applied, the sub-lemma becomes a nested entry and the register label moves to it:

```xml
<sense xml:id="angoisse_s3">
  <def>Poire d'angoisse, poire d'un goût très âpre.</def>
  <entry xml:id="angoisse_avaler_des_poires_d_angoisse" type="relatedEntry" xml:lang="fr-x-lit19c">
    <form type="lemma"><orth value="avaler des poires d'angoisse"/></form>
    <sense xml:id="angoisse_avaler_des_poires_d_angoisse_s1">
      <usg type="socioCultural" norm="familiar">familièrement.</usg>
      <def>subir des mortifications, de vifs déplaisirs.</def>
      <cit type="example">
        <quote>Je vous présente des poires de bon-chrétien pour des poires d'angoisse ...</quote>
        <bibl><author>MOL.</author><biblScope>Escarb. 15</biblScope></bibl>
      </cit>
    </sense>
  </entry>
</sense>
```

The same facts go to SQLite, where the node, its constituents, the qualification and its target, and the citation are all queryable, each keyed to its position in the source.

The `xml:id` values are made by the renderer for the document it is writing. Adjudication refers to material by classification surface and projected interval, so these identifiers carry no judgment and are free to change when structure does.

## Where to go next

`semantic-model.md` develops the node, qualification, relation and scope model, and states the closure rules precisely.

`source-representation.md` covers the two views of the source, patching, and how projected intervals are mapped back to source positions.

`adjudication-authoring.md` covers the harness that produces records, what it will refuse, and why.

`adjudication-rendering.md` covers how records are applied at build time and what each renderer may and may not do.

`tei-lex0-compliance.md` and `tei-lex0-examples.md` cover the serialization contract against the pinned schema.
