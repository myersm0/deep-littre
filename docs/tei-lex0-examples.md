# TEI Lex-0 examples for Deep-Littré

Status: **normative worked examples for v0.3**.

Companion to `tei-lex0-compliance.md`. These examples are not a chronological record of the July compliance pass. They show the structures the v0.3 renderer should produce after semantic adjudication, while distinguishing them from coarse output that remains valid before adjudication is complete.

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

- every `<entry>` has `xml:id` and `xml:lang`;
- top-level entries are `type="mainEntry"`;
- `<form>` is typed;
- entry grammar is a direct child of `<entry>`;
- the lemma `<orth>` preserves the printed headword; casing normalization is not published merely because the renderer can compute it internally.

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

The development corpus contains:

```xml
<indent><semantique type="indicateur">Familièrement.</semantique> Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.
```

v0.2 can preserve the register fact but leaves the multiword unit inside the definition:

```xml
<sense xml:id="angoisse_s3.1">
  <usg type="socioCultural" norm="familiar">familièrement.</usg>
  <def>Avaler des poires d'angoisse, subir des mortifications, de vifs déplaisirs.</def>
  ...
</sense>
```

After v0.3 adjudication establishes both a `SubLemma` and the scope of the register qualification, the target is structurally richer:

```xml
<sense xml:id="angoisse_s3">
  <def>Poire d'angoisse, poire d'un goût très âpre.</def>
  <entry xml:id="angoisse_avaler_des_poires_d_angoisse"
         xml:lang="fr-x-lit19c"
         type="relatedEntry">
    <form type="lemma">
      <orth value="avaler des poires d'angoisse"/>
    </form>
    <sense xml:id="angoisse_avaler_des_poires_d_angoisse_s1">
      <usg type="socioCultural" norm="familiar">familièrement.</usg>
      <def>subir des mortifications, de vifs déplaisirs.</def>
      <cit type="example">
        <quote>Je vous présente des poires de bon-chrétien pour des poires d'angoisse que vos cruautés me font avaler tous les jours</quote>
        <bibl><author>MOL.</author><biblScope>Escarb. 15</biblScope></bibl>
      </cit>
    </sense>
  </entry>
</sense>
```

The exact published `xml:id` is a renderer concern; the semantic facts are the anchored sub-lemma, its form/gloss constituents, and the qualification targeted to it.

## 4. Figurative qualification plus sub-lemma: BOUE

Sample source:

```xml
<indent><semantique type="indicateur">Fig.</semantique> Bâtir sur la boue, se bercer de vaines espérances.
```

v0.2 serializes the figurative reading as a nested sense:

```xml
<sense xml:id="boue_s2.2" ana="figurative">
  <usg type="meaningType" norm="figurative">fig.</usg>
  <def>Bâtir sur la boue, se bercer de vaines espérances.</def>
</sense>
```

v0.3 removes the redundant `ana` classification and can represent the multiword unit independently. The `relatedEntry` remains nested inside the containing sense:

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

Again, this is possible because `meaningType=figurative` and `SubLemma` are independent facts rather than competing `IndentRole` values.

## 5. Implicit sub-lemma: CABINET

The July analysis identified:

```text
Tenir cabinet, tenir conseil.
```

as a form/gloss pair embedded in definition prose.

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

The July worked example also exposed the opposite error. A sentence such as:

```text
Le cabinet tout entier donna sa démission
```

was at one point emitted as a locution form even though the following definition explains a metonymic sense of *cabinet* (the members of the council).

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

The July example for FLEURER used:

```xml
<note type="remarque">
  ...
  <dictScrap>
    <cit type="example">...</cit>
  </dictScrap>
</note>
```

That pattern is obsolete for this project because the pinned RNG rejects `<dictScrap>`.

The renderer instead uses a probed schema-valid arrangement. In v0.2, note/rubrique prose and citations are separated where necessary, with citations emitted at an allowed sibling level. v0.3 preserves that rule unless a new probe establishes a better valid structure.

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

In v0.3 that distinction should be established by an explicit adjudication/property path rather than by renderer-length or keyword heuristics.

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
