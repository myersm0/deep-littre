# TEI Lex-0 examples for Deep-Littré

Status: sections 1–15 are **normative worked examples for v0.3**. Section 16 is provisional for v0.4.

Companion to `tei-lex0-compliance.md`. These examples show the structures the renderer should produce after semantic adjudication, alongside the coarse output that remains valid before adjudication is complete.

All examples target the pinned TEI Lex-0 v0.9.5 RNG. When an example and the probe disagree, the probe/schema wins and this file must be updated.

## 1. Entry shell

```xml
<entry xml:id="agamie" xml:lang="fr-x-lit19c" type="mainEntry">
  <form type="lemma">
    <orth>AGAMIE</orth>
    <pron>a-ga-mie</pron>
  </form>
  <gramGrp>
    <gram type="pos" norm="noun">s.</gram>
    <gram type="gender" norm="feminine">f.</gram>
  </gramGrp>
  <sense xml:id="agamie_s1">
    <usg type="domain" norm="botany">terme de botanique.</usg>
    <def>État des plantes agames. ...</def>
  </sense>
</entry>
```

Important points:

- every `<entry>` has `xml:id` and `xml:lang`
- top-level entries are `type="mainEntry"`
- `<form>` is typed
- entry grammar is a direct child of `<entry>`
- the lemma `<orth>` preserves the printed headword, casing included

## 2. Cross-reference in etymology: AGAMIE

Source content is essentially *Voy. AGAME*.

Target:

```xml
<etym>
  <xr type="related">
    <lbl>Voy.</lbl>
    <ref type="entry" target="#agame">AGAME</ref>
  </xr>
</etym>
```

The cross-reference is a relation. `Voy.` belongs inside the `<xr>` as `<lbl>`. The internal target is emitted only because the referenced entry id is known.

## 3. One source block, several semantic facts: ANGOISSE

The development corpus contains, inside the entry's third sense:

```xml
<indent><semantique type="indicateur">Familièrement.</semantique> Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.
<cit aut="MOL." ref="Escarb. 15">Je vous présente des poires de bon-chrétien pour des poires d'angoisse que vos cruautés me font avaler tous les jours</cit>
</indent>
```

Before adjudication, the register fact is preserved and the multiword unit stays inside the definition. The indent is a block, so it takes its own positional slot beneath the variante:

```xml
<sense xml:id="angoisse_s3" n="3">
  <def>Poire d'angoisse, poire d'un goût très âpre.</def>
  <sense xml:id="angoisse_s3.1">
    <usg type="socioCultural" norm="familiar">Familièrement.</usg>
    <def>Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.</def>
    <cit type="example" xml:id="angoisse_c2">
      <quote>Je vous présente des poires de bon-chrétien pour des poires d'angoisse que vos cruautés me font avaler tous les jours</quote>
      <bibl>
        <author>MOL.</author>
        <biblScope>Escarb. 15</biblScope>
      </bibl>
    </cit>
  </sense>
  <sense xml:id="angoisse_s3.2">
    <def>Poire d'angoisse, espèce de bâillon en fer dont se servaient les voleurs pour étouffer les cris.</def>
  </sense>
</sense>
```

Once adjudication establishes the `SubLemma` and the scope of the register qualification, the unit becomes a nested entry and the label moves onto it. The `angoisse_s3.1` slot remains, because the block remains: the sense that occupies it now carries the nested entry and nothing else, its printed content having been claimed by the marker and the sub-lemma's constituents.

```xml
<sense xml:id="angoisse_s3" n="3">
  <def>Poire d'angoisse, poire d'un goût très âpre.</def>
  <sense xml:id="angoisse_s3.1">
    <entry xml:id="angoisse_avaler_des_poires_d_angoisse"
           xml:lang="fr-x-lit19c"
           type="relatedEntry">
      <form type="lemma">
        <orth value="avaler des poires d'angoisse"/>
      </form>
      <pc>,</pc>
      <sense xml:id="angoisse_avaler_des_poires_d_angoisse_s1">
        <usg type="socioCultural" norm="familiar">Familièrement.</usg>
        <def>subir des mortifications, de vifs déplaisirs.</def>
        <cit type="example" xml:id="angoisse_c2">
          <quote>Je vous présente des poires de bon-chrétien pour des poires d'angoisse que vos cruautés me font avaler tous les jours</quote>
          <bibl>
            <author>MOL.</author>
            <biblScope>Escarb. 15</biblScope>
          </bibl>
        </cit>
      </sense>
    </entry>
  </sense>
  <sense xml:id="angoisse_s3.2">
    <def>Poire d'angoisse, espèce de bâillon en fer dont se servaient les voleurs pour étouffer les cris.</def>
  </sense>
</sense>
```

Both shapes are true of the same source. The coarse one asserts less; neither invents anything Littré did not print. The published `xml:id` values are a renderer concern, and the printed label keeps its capital, since `<usg>` carries the marker text as printed. What adjudication contributed is the sub-lemma, its form and gloss constituents, and the qualification's target.

## 4. Figurative qualification plus sub-lemma: BOUE

Sample source:

```xml
<indent><semantique type="indicateur">Fig.</semantique> Bâtir sur la boue, se bercer de vaines espérances.
```

Coarse output serializes the figurative reading as a nested sense:

```xml
<sense xml:id="boue_s2.2" ana="figurative">
  <usg type="meaningType" norm="figurative">fig.</usg>
  <def>Bâtir sur la boue, se bercer de vaines espérances.</def>
</sense>
```

After adjudication the multiword unit is represented independently, and the redundant `ana` classification is gone. The `relatedEntry` nests inside the containing sense:

```xml
<sense xml:id="boue_s2">
  <def>...</def>
  <entry xml:id="boue_batir_sur_la_boue"
         xml:lang="fr-x-lit19c"
         type="relatedEntry">
    <form type="lemma"><orth value="bâtir sur la boue"/></form>
    <sense xml:id="boue_batir_sur_la_boue_s1">
      <usg type="meaningType" norm="figurative">fig.</usg>
      <def>se bercer de vaines espérances.</def>
    </sense>
  </entry>
</sense>
```

As with ANGOISSE, this works because `meaningType=figurative` and `SubLemma` are independent facts about the same material.

## 5. Implicit sub-lemma: CABINET

Here a form/gloss pair sits embedded in definition prose, with nothing in the markup to set it off:

```text
Tenir cabinet, tenir conseil.
```

After adjudication, the related entry is nested inside the containing sense:

```xml
<sense xml:id="cabinet_s4">
  <def>...</def>
  <entry xml:id="cabinet_tenir_cabinet"
         xml:lang="fr-x-lit19c"
         type="relatedEntry">
    <form type="lemma">
      <orth value="tenir cabinet"/>
    </form>
    <sense xml:id="cabinet_tenir_cabinet_s1">
      <def>tenir conseil.</def>
      <cit type="example">
        <quote>On tenait cabinet mal à propos, l'on donnait des rendez-vous sans sujet</quote>
        <bibl><author>RETZ</author><biblScope>II, 65</biblScope></bibl>
      </cit>
    </sense>
  </entry>
</sense>
```

`orth/@value` records that the canonical form is an editorial decomposition of source prose rather than a separately printed lemma field.

The old `<re type="locution">` route is not used.

## 6. A supposed locution that is really a sub-sense: CABINET

The opposite error is just as easy to make. A sentence such as:

```text
Le cabinet tout entier donna sa démission
```

reads like a form, but the following definition explains a metonymic sense of *cabinet*, the members of the council. It is an example, not a sub-lemma.

Target after adjudication:

```xml
<sense xml:id="cabinet_metonymic_council_members">
  <def>Les membres du conseil.</def>
  <cit type="example">
    <quote>Le cabinet tout entier donna sa démission.</quote>
  </cit>
  <cit type="example">
    <quote>Une partie du cabinet fut changée.</quote>
  </cit>
</sense>
```

The distinction is semantic and is not inferred from comma placement, sentence length, or the presence of a source tag alone.

## 7. Compound usage labels

A printed label such as:

```text
familièrement et fig.
```

may produce two independent qualifications:

```xml
<usg type="socioCultural" norm="familiar">familièrement</usg>
<usg type="meaningType" norm="figurative">fig.</usg>
```

There is no `<usg type="register">` umbrella in released TEI.

## 8. Proverbial status

Proverbial is a `meaningType` value, not a node type or independent property axis:

```xml
<entry xml:id="..." xml:lang="fr-x-lit19c" type="relatedEntry">
  <form type="lemma"><orth value="..."/></form>
  <sense xml:id="...">
    <usg type="meaningType" norm="proverbial">prov.</usg>
    <def>...</def>
  </sense>
</entry>
```

Whether the proverb is a `SubLemma` or belongs on an ordinary sense is an adjudication question separate from the proverbial qualification.


Before a proverb has been adjudicated as entry-shaped, its rubrique may remain coarse while still
preserving the printed heading and its lifted attestation:

```xml
<note type="proverb" xml:id="enfanter_proverb_1"><seg type="label">Proverbe.</seg> <seg type="example">C'est la montagne qui enfante une souris</seg>, ou <seg type="example">la montagne a enfanté une souris</seg>, se dit de grands projets qui viennent à rien.</note>
<cit type="example" xml:id="enfanter_c21" subtype="proverb" corresp="#enfanter_proverb_1">
  <quote>Que produira l'auteur après tous ces grands cris ? La montagne en travail enfante une souris</quote>
  <bibl><author>BOILEAU</author><biblScope>Art p. III</biblScope></bibl>
</cit>
```

The single note distinguishes the printed heading with `seg/@type="label"` instead of manufacturing a
second proverb note. `@corresp` preserves the relationship to a citation that Lex-0 requires to be
lifted outside the note. If adjudication later establishes a `SubLemma`, the proverb becomes a
`relatedEntry` and its citation can live inside that semantic node instead.

## 9. Etymons and cognate: ACCOUPLER pattern

The reviewed ACCOUPLER etymology is a useful canonical case because it contains compound sources,
an unmarked connector, punctuation, a regional label, and a cognate:

```xml
<etym>
  <cit type="etymon" xml:lang="fr"><form><orth rend="italic">À</orth></form></cit> et <cit type="etymon" xml:lang="fr"><form><orth rend="italic">couple</orth></form></cit> <pc>;</pc> <cit type="cognate" xml:lang="fr-x-berrich"><lang expand="berrichon" norm="fr-x-berrich">Berry</lang><pc>,</pc><form><orth rend="italic">accoubler</orth></form></cit><pc>.</pc>
</etym>
```

`À` and `couple` are lexical sources of the compound, so they use Lex-0's standard `cit/@type="etymon"`
rather than a project-specific component type. `accoubler` is the cognate. Source capitalization and
etymological italics are preserved, unmarked `et` remains ordinary text, and punctuation is emitted
as `<pc>` in source order.

## 10. Historical attestations are siblings of `<etym>`

Historical material from `HISTORIQUE` is not folded into the etymological account. Century labels and
attestations serialize at entry level, parallel to `<etym>`:

```xml
<lbl type="dateRange">XVe s.</lbl>
<cit type="example" xml:id="tronquer_c1" subtype="attestation">
  <quote>Icellui Perrenet se print à copper et troncer lesdiz ormes</quote>
  <bibl>
    <author>DU CANGE</author>
    <biblScope>troncire.</biblScope>
    <date notBefore="1401" notAfter="1500">XVe s.</date>
  </bibl>
</cit>
<lbl type="dateRange">XVIe s.</lbl>
<cit type="example" xml:id="tronquer_c2" subtype="attestation">
  <quote>Un corps tronqué de teste</quote>
  <bibl>
    <author>RONS.</author>
    <biblScope>675</biblScope>
    <date notBefore="1501" notAfter="1600">XVIe s.</date>
  </bibl>
</cit>
<etym>...</etym>
```

`subtype="attestation"` carries the diachronic distinction while `cit/@type` stays within the pinned
schema's closed vocabulary. `@ana` is not used for this processing/structural distinction.

## 11. Reconstructed etymon and suspect token: VOULOIR pattern

```xml
<cit type="etymon" xml:lang="la">
  <lang expand="latin" norm="la">lat.</lang>
  <usg type="hint">fictif</usg>
  <form><orth>volere</orth></form>
</cit>
<lbl>re</lbl>
<cit type="cognate" xml:lang="grc">
  <form><orth>βούλομαι</orth></form>
</cit>
```

If `re` is unresolved source damage, preserve it visibly and mark the epistemic state when the pinned schema admits the annotation:

```xml
<lbl ana="suspect">re</lbl>
```

Do not silently normalize it to a guessed abbreviation.

## 12. Remarque citations: no `<dictScrap>`

An earlier FLEURER encoding used:

```xml
<note type="remarque">
  ...
  <dictScrap>
    <cit type="example">...</cit>
  </dictScrap>
</note>
```

The pinned RNG rejects `<dictScrap>`, so the renderer uses a probed schema-valid arrangement instead: note and rubrique prose are separated from citations where necessary, with the citations emitted at an allowed sibling level. That rule holds unless a new probe establishes a better valid structure.

The important requirement is that the citation remains represented and associated through the semantic/source model; the renderer must not invent an invalid wrapper to mimic the print nesting.

## 13. Pronunciation prose

A normal pronunciation:

```xml
<form type="lemma">
  <orth>AGAMIE</orth>
  <pron>a-ga-mie</pron>
</form>
```

Prescriptive prose that Littré happens to place in the pronunciation field may instead be represented as:

```xml
<note type="pronunciation">...</note>
```

That distinction should be established by an explicit adjudication or property path rather than by renderer-length or keyword heuristics.

## 14. Coarse serialization before adjudication

Suppose a source block contains prose whose finer structure has not yet been adjudicated. It may still be released as:

```xml
<sense xml:id="...">
  <def>...</def>
</sense>
```

Do not add:

```xml
ana="unclassified"
```

The authoritative adjudication store records whether the relevant passes are unrun, negative, or unresolved. The TEI tree simply refrains from making a finer claim.

## 15. Workflow state versus corpus claims

These are appropriate corpus-facing annotations in the current project convention:

```xml
<cit type="example" subtype="attestation">...</cit>
<lbl ana="suspect">...</lbl>
```

because they state something about the represented material: `subtype="attestation"` is a corpus-facing citation distinction, while `ana="suspect"` is an explicit editorial epistemic claim.

This is not:

```xml
<sense ana="unclassified">...</sense>
```

because it states that the pipeline has not settled a classification. That information belongs in adjudication provenance and coverage records.

## 16. Decomposition carrier: cited forms and glosses

Status: **provisional, v0.4**.

The decomposition pass marks stretches of a block as cited forms of the headword, and the text, if any, that glosses each. It asserts nothing about what kind of thing a form/gloss pair is. Promotion of some pairs to `<entry type="relatedEntry">` or `<entry type="homonymicEntry">` is a later stage. These shapes are the default carrier: the weakest honest claim, chosen so that an unrun later stage degrades to under-claiming rather than to error.

A **gloss** defines the form. A **definition** defines the headword. `<gloss>` is permitted inside `cit` and `<def>` is not, so the schema keeps the two apart on its own.

In this carrier, `cit/@type="example"` means *cited form pending promotion*, not *illustrative example proper*. `cit/@type` is a closed list — `cognate`, `cognateSet`, `etymon`, `example`, `translation`, `translationEquivalent` — and `example` is the only admissible wrapper for a glossed phrase. The type value does almost no work; the meaning is carried by the presence of `<gloss>` and by the schema's refusal of `<def>` in this position. Do not read the label as a claim that the material is an example.

### 16.1 Form with gloss: BANQUE

Source: `Maison de banque, maison qui s'occupe principalement des opérations de banque.`

```xml
<sense xml:id="banque.1">
  <cit type="example">
    <form type="phrase"><orth>Maison de banque</orth></form><pc>,</pc>
    <gloss>maison qui s'occupe principalement des opérations de banque</gloss><pc>.</pc>
  </cit>
</sense>
```

`<form>` plus `<gloss>` directly in the `<sense>`, with no `cit` at all, also validates and makes no type claim. It is rejected as the default because a `cit` explicitly groups one form with its gloss, whereas loose siblings bind only by adjacency — ambiguous as soon as a sense holds more than one pair.

### 16.2 Forms without gloss: DISTINGUÉ

Source: `Qui porte le caractère de la distinction, de l'éminence, en parlant des personnes. Un personnage distingué. Des savants distingués.`

```xml
<sense xml:id="distingue.1">
  <usg type="hint">en parlant des personnes</usg>
  <def>Qui porte le caractère de la distinction, de l'éminence</def><pc>.</pc>
  <cit type="example"><quote>Un personnage distingué</quote></cit><pc>.</pc>
  <cit type="example"><quote>Des savants distingués</quote></cit><pc>.</pc>
</sense>
```

The definition defines the headword, not the examples, so it is `<def>` and the examples are unglossed. Gloss presence selects the element without anyone deciding a type: `<form><orth>` when glossed, `<quote>` when not. Two unglossed forms are two nodes — nothing binds them without a shared gloss.

`usg type="hint"` remains the honest home for a referent restriction: the schema has no `<colloc>` and no `usg/@type` meaning a selectional restriction. It is the sense's first child and governs the sense.

### 16.3 Form embedded in a remark: DISPUTER

Source, under `<rubrique nom="REMARQUE">`: `1. Disputer quelqu'un, pour dire lui faire querelle, n'est pas dans le Dictionnaire de l'Académie ; mais il est du langage familier et autorisé par quelques écrivains.`

The adjudicated record is one node with a form and a gloss constituent. Two serializations are available from it, and the choice is the renderer's.

Extracting a `cit`, with the remainder as a sibling note:

```xml
<sense xml:id="disputer.remarque.1" n="1">
  <cit type="example">
    <form type="phrase"><orth>Disputer quelqu'un</orth></form>
    <gloss>pour dire lui faire querelle</gloss>
  </cit>
  <note type="remark">, n'est pas dans le Dictionnaire de l'Académie ; mais il est du
    langage familier et autorisé par quelques écrivains.</note>
</sense>
```

Or marking inline and leaving Littré's sentence whole:

```xml
<sense xml:id="disputer.remarque.1" n="1">
  <note type="remark"><seg type="form">Disputer quelqu'un</seg>, <gloss>pour dire lui
    faire querelle</gloss>, n'est pas dans le Dictionnaire de l'Académie ; mais il est
    du langage familier et autorisé par quelques écrivains.</note>
</sense>
```

Review prefers the second. The residual fragment in the first is not the reason — fragmentary residuals are expected and deliberate in this scheme. The reason is contiguity: under the split, the remark is no longer one text node, and reconstructing it means joining across an element boundary, which is noise for search over running prose. The cost is a lighter form marking, and a query for cited forms must union `form[@type='phrase']/orth` with `seg[@type='form']`.

If adopted, state it as a rule for rubrique-embedded forms, not as a special case. Note that `<note>` admits `seg` and `gloss` but not `cit`, so only the second shape can keep the sentence whole.

`note/@type="remark"` is defensible because *remark* is a genuine note kind. Do not generalize it into a rubrique-name-to-`@type` mapping: HISTORIQUE and PROVERBES do not become notes at all, and SUPPLÉMENT would be provenance in an attribute meant for kind. Rubric provenance belongs in the `@ana`/`@corresp` channel.

### 16.4 Cited sentence with a paraphrase: FOSSÉ

Source, under `<rubrique nom="PROVERBES">`: `Ce qui tombe dans le fossé est pour le soldat, c'est-à-dire ce qu'on laisse tomber est pour celui qui le ramasse.`

```xml
<sense xml:id="fosse.proverbes.1">
  <cit type="example">
    <form type="phrase"><orth>Ce qui tombe dans le fossé est pour le soldat</orth></form><pc>,</pc>
    <gloss>c'est-à-dire ce qu'on laisse tomber est pour celui qui le ramasse</gloss><pc>.</pc>
  </cit>
</sense>
```

The paraphrase restates the whole cited clause rather than defining a word inside it. UTI POSSIDETIS takes the same shape, with its preceding definition left as `<def>`.

The gloss retains its introducing formula. `pour dire`, `c'est-à-dire` and kin are a small closed set, recoverable at the head of a gloss span; `<lbl>` inside `cit` is their home if they are ever separated.

### 16.5 Where a gloss ends

A gloss ends where the form is fully defined. COUFIQUE reads:

> Terme de philologie. Caractères coufiques, caractères dont se servaient les Arabes avant le IVe siècle de l'hégire. L'écriture coufique n'a pas de points diacritiques.

`caractères dont se servaient les Arabes avant le IVe siècle de l'hégire` defines `Caractères coufiques` completely, so the gloss is over. The sentence after it predicates a property of a different nominal and is neither gloss nor cited form; it stays as prose in the parent sense.

Littré's glosses are appositive noun phrases; his unattributed examples are bare fragments. An independent declarative with a finite verb has the shape of neither, which is the usable signal.

### 16.6 Punctuation

Two different operations, not to be conflated.

**Separators between constituents** are lifted to `<pc>` unconditionally. The comma in `Maison de banque, maison qui…` falls between two adjudicated spans and belongs to neither.

**Terminal punctuation of a form** depends on what the form is. If the form text is a complete sentence, its terminal punctuation is part of the quoted sentence and stays inside `<quote>`. If the form is an isolated phrase, the terminal punctuation is a separator — Littré is not attesting that the period belongs to the expression — and is lifted to `<pc>`:

```xml
<sense xml:id="chevroter.1">
  <def>Dans la musique, battre d'une manière inégale les deux notes d'un trille</def><pc>.</pc>
  <note>Il est actif aussi</note><pc>:</pc>
  <cit type="example"><quote>chevroter un trille</quote></cit><pc>.</pc>
</sense>
```

The motivation is corpus search as much as fidelity. CQL-style queries over multiword units — anchored patterns like `^[upos="VERB"] [lemma="un"] [upos="NOUN"]$`, or constraints on unit length — are polluted by a trailing period carrying no semantic weight.

The adjudicator selects by token, so a phrase ending a sentence is recorded with its period (`chevroter un trille.`). That is an artifact of selection granularity, not a claim, and is not honoured here. Whether the trim happens at render time or has to reach the record depends on which artifact corpus search runs over — open.

### 16.7 Degradation

A block with no decomposition record, or with one whose later characterization has not run, serializes as in section 14: a `<sense>` with a `<def>` and no finer claim. Nothing above should ever require a later reviewer to *undo* an assertion — only to refine one. 16.1 refines upward into a `relatedEntry` with nothing reversed; 16.2 is already stable; 16.3's inline form marks without restructuring, which is why review prefers it.
