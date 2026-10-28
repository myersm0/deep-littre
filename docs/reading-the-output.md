# Reading Deep-Littré's output

Read this first if you're new to Littré's dictionary, to XMLittré or to TEI Lex-0. It follows one short entry, APOTHICAIRE ("apothecary"), from XMLittré's markup to Deep-Littré's TEI and SQLite output, and introduces the terms the other reader-facing documents use, such as [`known-limitations.md`](known-limitations.md) and [`tei-lex0-examples.md`](tei-lex0-examples.md). APOTHICAIRE is one of the entries in the test corpus, in `test/corpus/source/a.xml`, so you can check each snippet against the repository.

## The entry in XMLittré

This is the whole entry as Gannaz transcribed it in his XMLittré:

```xml
<entree terme="APOTHICAIRE">
<entete>
	<prononciation>a-po-ti-kê-r'</prononciation>
	<nature>s. m.</nature>
</entete>
<corps>
<variante>Celui qui prépare et vend des médicaments. Pharmacien est présentement plus usité.
<indent><semantique type="indicateur">Familièrement.</semantique> 
<cit aut="SAINT-SIMON" ref="64, 56">M. de Brissac avait infiniment d'esprit, avec une figure de plat apothicaire</cit>
</indent>
<indent>Mémoire d'apothicaire, compte sur lequel il y a beaucoup à rabattre.
</indent>
<indent>Faire de son corps une boutique d'apothicaire, faire abus de médicaments.
</indent>
<indent>Un apothicaire sans sucre, un homme qui n'est pas fourni des choses de sa profession.
</indent>
</variante>
</corps>
<rubrique nom="HISTORIQUE">
<indent>XIIIe s. 
<cit aut="" ref="Liv. des mét. 322">Tuit cirier, tuit pevrier, et tuit apotecaire, se il metent avant au samedi es hales ou u marchié, chascun doit obole de coutume</cit>
<cit aut="RUTEB." ref="37">Fisicien, n'apoticaire, Ne me puent doner santé</cit>
</indent>
</rubrique>
<rubrique nom="ÉTYMOLOGIE">
<indent>Bas-lat. <i lang="la">apothecarius</i>, du latin <i lang="la">apotheca</i>, du grec ἀποθήϰη, boutique, de ἀπὸ, indiquant la mise à l'écart, en réserve, et de τίθημι, mettre (voy. <a ref="thème">THÈME</a> et <a ref="boutique">BOUTIQUE</a>).
</indent>
</rubrique>
</entree>
```

XMLittré's element names are French, and each one corresponds to a part of Littré's printed entry.

The *header* (`<entete>`) comes first. It gives the pronunciation, in Littré's own respelling with the syllables separated by hyphens, and the grammatical category, in `<nature>`. Littré abbreviates grammar, and these are the abbreviations you'll see most often:

| Abbreviation | Stands for | Meaning |
|---|---|---|
| *s. m.* | substantif masculin | masculine noun |
| *s. f.* | substantif féminin | feminine noun |
| *adj.* | adjectif | adjective |
| *adv.* | adverbe | adverb |
| *v. a.* | verbe actif | transitive verb |
| *v. n.* | verbe neutre | intransitive verb |
| *v. réfl.* | verbe réfléchi | reflexive verb |

The header is sometimes longer. It can include a conjugation, a second spelling of the headword, or a remark, and that extra material is where some of the limitations in `known-limitations.md` come from.

The *body* (`<corps>`) contains the senses. Each `<variante>` is one *sense* of the word. When a word has several, Littré numbers them, and XMLittré records the number as `num="1"`, `num="2"` and so on. APOTHICAIRE has only one sense, so it isn't numbered. Within a sense, each `<indent>` is a *subdivision*: a narrower use of the sense, an expression built on the word, or a quotation set apart. In print, Littré separates these with `||`.

A *label* (`<semantique>`) says how a sense or a subdivision is used. Here *Familièrement.* ("familiarly") says that the subdivision it opens is colloquial. Other labels give a subject area, such as *Terme de botanique.* ("botanical term"), or mark a use as figurative (*Fig.*) or old-fashioned.

A *quotation* (`<cit>`) is a passage from an author that illustrates the sense. `aut` contains the author as Littré printed the name, often abbreviated (*RUTEB.* is Rutebeuf), and `ref` says where in the author's work the passage comes from. `aut` is empty when Littré gives no author, as in the first quotation in the HISTORIQUE section.

After the body come the *named sections* (`<rubrique>`), which XMLittré calls rubriques. HISTORIQUE gives older forms and uses of the word, grouped by century (*XIIIe s.* is the 13th century). ÉTYMOLOGIE gives the word's origin. The others are REMARQUE (usage notes), SYNONYME (how the word differs from near-synonyms), PROVERBE or PROVERBES, and SUPPLÉMENT AU DICTIONNAIRE (additions from Littré's 1877 supplement).

A *cross-reference* (`<a>`) points to another entry. Littré introduces it with *voy.*, short for *voyez*. The printed text, here *THÈME*, is the element's content. The entry it points to is in `ref`, usually as the headword in lower case. When several entries share a spelling, Littré numbers them as *homographs*, such as FAIRE 1 (the verb *faire*) and FAIRE 2 (the noun *le faire*). A reference can give the number too. DÎNÉ, for instance, reads *Voy. DÎNER 2*, and its `ref` is `dîner.2`.

## The entry in TEI

Here is APOTHICAIRE as Deep-Littré publishes it, with the etymology shortened:

```xml
<entry xml:id="apothicaire" xml:lang="fr-x-lit19c" type="mainEntry">
	<form type="lemma"><orth>APOTHICAIRE</orth><pron>a-po-ti-kê-r'</pron></form>
	<gramGrp>
		<gram type="pos" norm="noun">s.</gram>
		<gram type="gender" norm="masculine">m.</gram>
	</gramGrp>
	<sense xml:id="apothicaire_s1">
		<def>Celui qui prépare et vend des médicaments. Pharmacien est présentement plus usité.</def>
		<sense xml:id="apothicaire_s1.1">
			<usg type="socioCultural" norm="familiar">Familièrement.</usg>
			<cit type="example" xml:id="apothicaire_c1">
				<quote>M. de Brissac avait infiniment d'esprit, avec une figure de plat apothicaire</quote>
				<bibl>
					<author>SAINT-SIMON</author>
					<biblScope>64, 56</biblScope>
				</bibl>
			</cit>
		</sense>
		<sense xml:id="apothicaire_s1.2">
			<def>Mémoire d'apothicaire, compte sur lequel il y a beaucoup à rabattre.</def>
		</sense>
		<sense xml:id="apothicaire_s1.3">
			<def>Faire de son corps une boutique d'apothicaire, faire abus de médicaments.</def>
		</sense>
		<sense xml:id="apothicaire_s1.4">
			<def>Un apothicaire sans sucre, un homme qui n'est pas fourni des choses de sa profession.</def>
		</sense>
	</sense>
	<lbl type="dateRange">XIIIe s.</lbl>
	<cit type="example" xml:id="apothicaire_c2" subtype="attestation">
		<quote>Tuit cirier, tuit pevrier, et tuit apotecaire, se il metent avant au samedi es hales ou u marchié, chascun doit obole de coutume</quote>
		<bibl>
			<biblScope>Liv. des mét. 322</biblScope>
			<date notBefore="1201" notAfter="1300">XIIIe s.</date>
		</bibl>
	</cit>
	<cit type="example" xml:id="apothicaire_c3" subtype="attestation">
		<quote>Fisicien, n'apoticaire, Ne me puent doner santé</quote>
		<bibl>
			<author>RUTEB.</author>
			<biblScope>37</biblScope>
			<date notBefore="1201" notAfter="1300">XIIIe s.</date>
		</bibl>
	</cit>
	<etym>
		[...]
		du <cit type="etymon" xml:lang="la"><lang expand="latin" norm="la">latin</lang><form><orth rend="italic">apotheca</orth></form></cit>
		du <cit type="etymon" xml:lang="grc"><lang expand="grec" norm="grc">grec</lang><form><orth>ἀποθήϰη</orth></form></cit>
		[...]
		<pc>(</pc><lbl>voy.</lbl><ref type="entry" target="#theme">THÈME</ref><seg>et</seg><ref type="entry" target="#boutique">BOUTIQUE</ref><pc>)</pc><pc>.</pc>
	</etym>
</entry>
```

Most of XMLittré's parts have a direct counterpart. The headword and pronunciation go in `<form>`. The grammar goes in a `<gramGrp>`, with one `<gram>` for each category: *s.* is the part of speech and *m.* the gender. The text inside each element is what Littré printed, and `norm` gives a normalized English value, so you can search for `norm="noun"` without knowing that Littré writes *s.* for it.

Each sense becomes a `<sense>`, and each subdivision a `<sense>` nested inside it. The `xml:id` values follow the structure: `apothicaire_s1` is the first sense, and `apothicaire_s1.2` is its second subdivision. A sense that Littré numbers also has an `n` attribute with the printed number. A sense's own text goes in `<def>`.

A label becomes a *usage label* (`<usg>`), with `type` saying what kind of label it is and `norm` giving its value. *Familièrement.* is `type="socioCultural" norm="familiar"`. The `<usg>` sits at the start of the sense it applies to.

A quotation becomes a `<cit type="example">`, with the passage in `<quote>` and the author and reference in `<bibl>`. When Littré writes *ID.* ("same author") instead of a name, the `<author>` element keeps *ID.* and points back to the earlier quotation it repeats; the top-level README shows this for TRONQUER.

The named sections are handled one by one. HISTORIQUE doesn't become a section at all: its quotations become `<cit>` elements with `subtype="attestation"`, at entry level next to the senses, each with its century as a `<date>` range that you can compare and sort. ÉTYMOLOGIE becomes `<etym>`, in which each language and each form is its own element: the Latin *apotheca* is a `<cit>` with `xml:lang="la"`, and the Greek ἀποθήϰη is a `<cit>` with `xml:lang="grc"`. That's what lets you ask which entries derive from Greek. The other sections mostly become `<note>` elements, with `type` saying which section each came from: a REMARQUE becomes `<note type="usage">`, a SYNONYME `<note type="synonymy">`, and so on.

A cross-reference becomes a `<ref>`. When Deep-Littré can tell which entry is meant, `target` names that entry's `xml:id`: `target="#theme"` points to `<entry xml:id="theme">`, the entry THÈME. When it can't tell, the `<ref>` has no `target`. `known-limitations.md` explains when and why that happens.

The TEI doesn't yet show everything in the entry. The subdivision `apothicaire_s1.2` contains an expression, *Mémoire d'apothicaire* ("an apothecary's bill"), and its definition, *compte sur lequel il y a beaucoup à rabattre* ("a bill from which a great deal has to be taken off"). Nothing in XMLittré marks where one ends and the other begins, so for now both stay together in one `<def>`. Separating them is the job of what I call "the classification campaign," an ongoing project. Section 16 of `tei-lex0-examples.md` shows the shape the output will take.

## The entry in SQLite

The database contains the same facts in tables. These are the ones you'll use most:

| Table | One row per |
|---|---|
| `entries` | entry |
| `nodes` | sense or subdivision, with `parent_id` giving the tree |
| `qualifications` | grammatical category or usage label |
| `citations` | quotation, including the HISTORIQUE attestations |
| `rubriques` | named section |
| `etymology` | piece of an etymology: a form, a connecting word, a cross-reference |
| `content_segments` | piece of running text: plain text or a cross-reference |
| `header_notes` | stretch of extra header text |

For APOTHICAIRE, this query gives its grammar and labels:

```sql
select q.node_id, q.channel, q.type, q.norm, q.printed
from qualifications q join entries e on q.entry_id = e.entry_id
where e.headword = 'APOTHICAIRE';
```

```
node_id                 channel  type           norm        printed
                        gram     pos            noun        s.
                        gram     gender         masculine   m.
a.xml:3615950:3616146   usg      socioCultural  familiar    Familièrement.
```

The first two rows have no `node_id` because they belong to the entry as a whole. The third belongs to the subdivision `apothicaire_s1.1`. `channel` says whether the row is a grammatical category (`gram`) or a usage label (`usg`).

## Where each fact came from

Every row in the database records the place in XMLittré it came from, as a file and two byte offsets. The IDs are built the same way: APOTHICAIRE's `entry_id` is `a.xml:3615726:3617109`, and the node above is `a.xml:3615950:3616146`.

The offsets count bytes, not characters, from 1. The start is the first byte of the element, and the end is one past its last byte. So the entry occupies bytes 3,615,726 through 3,617,108 of `a.xml`, as Gannaz distributes it.

You can check this against the test corpus. Its `a.xml` holds only a few entries, so the offsets there are smaller: if you build the test corpus as `test/corpus/README.md` describes, APOTHICAIRE comes out as `a.xml:5287:6670`. In Julia:

```julia
julia> String(read("test/corpus/source/a.xml")[5287:6669])
"<entree terme=\"APOTHICAIRE\">\n<entete>\n\t<prononciation>a-po-ti-kê-r'</prononciation>\n [...] </entree>"
```

## Where to go next

[`known-limitations.md`](known-limitations.md) describes what the output doesn't do yet, and what that means for your queries. [`tei-lex0-examples.md`](tei-lex0-examples.md) shows how other kinds of entry are published. If you want to work on the pipeline itself, start with [`architecture/overview.md`](architecture/overview.md).
