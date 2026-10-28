# Known limitations

This page expands on the limitations listed in the [top-level README](../README.md#known-limitations). Each section starts with what the limitation looks like in the published output and what it means for your queries, using real entries as examples. It ends with a pipeline detail subsection, which states the limitation in the pipeline's own terms for anyone working on the code.

If you're new to Littré's conventions, to XMLittré or to TEI Lex-0, read [`reading-the-output.md`](reading-the-output.md) first. It explains the terms used here: header, sense, subdivision, label, named section and cross-reference, and how a fact's file and byte offsets are recorded. The examples on this page come from the v0.3.0 release, and so do the figures, unless a script is named as their source.

## Labels in an entry header are kept as plain text

Most of an entry's header comes out as structured elements: the pronunciation in `<pron>`, the grammar in `<gramGrp>`. Anything else Littré prints there is kept word for word in a `<note type="header">`. For TARGUER, that's a conjugation:

```xml
<note type="header">Je me targuais, nous nous targuions, vous vous targuiez ; que je me targue, que nous nous targuions, que vous vous targuiez</note>
```

For MÉLISSOT, it's a second name for the same plant, with its own pronunciation and gender:

```xml
<note type="header">ou MÉLISSIÈRE (mé-li-siè-r') s. f.</note>
```

That works well enough for text like this. The problem is subject-area labels. Sometimes the header has a label like *Technologie.* or *Terme de botanique.* ("botanical term"), and XMLittré marks it as one. Here is ANCRURE in XMLittré:

```xml
<entete>
	<prononciation>an-kru-r'</prononciation>
	<nature>s. f.</nature>
<indent><semantique type="domaine">Technologie.</semantique>
</indent>
</entete>
```

`<semantique type="domaine">` says that *Technologie.* is a subject area: both of ANCRURE's senses belong to the vocabulary of technology. Deep-Littré keeps the word but loses what XMLittré said about it:

```xml
<form type="lemma"><orth>ANCRURE</orth><pron>an-kru-r'</pron></form>
<gramGrp>
	<gram type="pos" norm="noun">s.</gram>
	<gram type="gender" norm="feminine">f.</gram>
</gramGrp>
<note type="header">Technologie.</note>
```

Compare HYPOCHILE. There the same kind of label opens a sense instead of sitting in the header, and it becomes a usage label:

```xml
<sense xml:id="hypochile_ou_hypochilion_s1">
	<usg type="domain">Terme de botanique.</usg>
	<def>Partie inférieure du tablier des orchidées.</def>
</sense>
```

So a search for `<usg type="domain">` finds HYPOCHILE but not ANCRURE. SQLite has the same gap: HYPOCHILE's label is a row in `qualifications`, while ANCRURE's exists only as text in `header_notes`.

This affects 99 entries. The output has no way to single them out, but searching header notes for the usual wording of a label finds many of them:

```sql
select e.headword, h.content
from header_notes h join entries e on h.entry_id = e.entry_id
where h.content like 'Terme %';
```

This is only an approximation. It misses labels with other wording, like ANCRURE's *Technologie.* It also finds labels that XMLittré itself left unmarked, where *Terme de musique.* or the like is plain text in the source. Those belong to the larger set of unmarked labels that the classification campaign will address.

### Pipeline detail

`entry_header` writes the entete material that is neither the entry's pronunciation nor a label qualifying it as `<note type="header">`, one note per contiguous run. Loose text, an `<indent>`, a cross-reference, and the pronunciation and label of a further headword form all join the run they sit in. If a run doesn't contain a letter or a digit, it's only separator punctuation, and no note is written for it.

`inline_from` builds the note through `gather_node!`, which has no branch for `<semantique>`. It recurses into the element and absorbs the text, so the printed label survives and the type Gannaz gave it doesn't. Anywhere else, `route_spans` carves the same element out and re-emits it as a `<usg>` with its type. The entete is the only place where the pipeline drops a type that the source states.

`bin/entete_report.jl` counts 99 `<semantique>` elements inside an entete. 90 open an `<indent>` and 9 are direct children of `<entete>`, and none sits anywhere else inside a block. 92 have `type="domaine"`, 4 have `type="indicateur"`, and 3 are untyped.

Recording the type would take a `<seg type="…">` inside the note. The pinned RNG gives `<note>` the content model `macro.lexSpecialPara`, which admits `model.segLike` but not `<usg>`. This is deferred. It would cost a field on `Emphasis`, a flag on `InlineBuilder`, and two new branches, all for 92 labels, and nothing downstream uses the type yet: header notes reach SQLite as flattened text and don't produce `content_segments`.

## Grammar stated as a phrase is left unclassified

Littré usually gives an entry's grammar as a short abbreviation, and Deep-Littré turns it into structured categories. ANCRURE's *s. f.*, for instance, becomes a noun with feminine gender, as shown above.

A few entries state their grammar as a phrase instead. A 2, the verb form *a* ("has"), reads *3e pers. sing. ind. prés. du verbe AVOIR.*: third person singular, present indicative, of the verb AVOIR. AULX reads *pluriel de AIL.*, "plural of AIL" (garlic). Deep-Littré doesn't try to break a phrase like this into categories. It publishes the text as Littré wrote it, as a usage label of type `hint` directly under the entry:

```xml
<entry xml:id="aulx" xml:lang="fr-x-lit19c" type="mainEntry">
	<form type="lemma"><orth>AULX</orth><pron>ô</pron></form>
	<usg type="hint">pluriel de AIL.</usg>
</entry>
```

In SQLite it's a row in `qualifications` with `type = 'hint'`. AULX has no `<gramGrp>` at all, so a search for nouns won't find it. And the `<usg>` claims too much: *pluriel de AIL.* isn't a usage label, and it doesn't qualify anything.

This query lists the 102 entries affected. F and SACHE each come up twice, because each has two phrases:

```sql
select e.headword, q.printed
from qualifications q join entries e on q.entry_id = e.entry_id
where q.type = 'hint' and q.node_id is null;
```

The phrases fall into three groups.

The first group is abbreviations that Deep-Littré's tables don't recognize. ACHETÉ, ÉE reads *p. passé.*, where Littré normally writes *part. passé* (past participle). ASINIFIER (S') reads *v. r.* instead of *v. réfl.* (reflexive verb). Both are left alone on purpose, as the pipeline detail explains.

The second group, and the largest, is grammar written out as a phrase. Besides A 2 and AULX, there's TIENS, *impér. de tenir.* (imperative of *tenir*), and APPARTENU, *part. passé invariable d'appartenir* (invariable past participle of *appartenir*). This group also includes some very common words. DÉJÀ, DEMAIN, ENCORE and many others are marked *adv. de temps*, rnd ICI and LÀ are *adv. de lieu*, The classification campaign is what will reduce this group.

The third group is a label mixed with commentary. MIMOSA reads *s. f. (mais d'après les botanistes, s. m)*: "feminine noun (but masculine, according to botanists)". PAMPLEMOUSSE reads *s. f. d'après l'Académie, mais s. m. d'après l'usage des lieux où croît cet arbre*: "feminine according to the Académie, but masculine according to usage where the tree grows". The entry for the letter F has two of these, one for each way of saying the letter's name:

```xml
<usg type="hint">s. f. quand on prononce cette lettre èf : une petite f ;</usg>
<usg type="hint">s. m. quand on la prononce fe : un f majuscule.</usg>
```

Six entries, among them PANSÉ, ÉE and VAINCU, UE, read *part passé*, with no period after *part*. That's a typo in XMLittré, and it belongs on the list of upstream defects to report, alongside `BARDÉ, ÉÉ` and `COUCHEUR. EUSE`.

### Pipeline detail

An entry-level `<nature>` goes to `route_spans`. It first tries to parse the whole string as a part of speech, then routes each atom through the agreement, construction, POS and register tables in turn. If no table claims an atom, it falls through to `UsgTarget("hint", "")` and is emitted as `<usg type="hint">` scoped over the entry. Nearly all of these atoms come from an entete `<nature>`, handled by `entry_grammar`, and none from a sense-level one, so a table row added for them affects the entete and nothing else.

The unrecognized abbreviations are spellings of parts of speech that the tables already know in another form. Most such spellings have rows in `data/pos_abbreviations.toml` and `data/usg_register_norms.toml`. `p.` for a participle and `r.` for a reflexive are deliberately absent: each would fix only one entry, and a single-letter token is too generic to claim across every `<nature>`.

No table row can match the grammatical phrases, because each atom is a construction rather than a label. The word `de` alone blocks 43 of them. For this group, scoping `<usg type="hint">` over the entry overclaims.

The header of `usg_gram_norms.toml` already names the mixed label-and-commentary group as `split_bare_transition` residue.

## Some cross-references have no link

Deep-Littré tries to turn each of Littré's *voy.* references into a link. When it succeeds, the `<ref>` gets a `target`. DÉPLAIRE's etymology, for instance, links to PLAIRE:

```xml
<pc>(</pc><lbl>voy.</lbl><ref type="entry" target="#plaire">PLAIRE</ref><pc>)</pc>
```

When it can't tell which entry is meant, it leaves the link out instead of guessing. This is from ACIDIFIER's etymology:

```xml
<pc>(</pc><lbl>voy.</lbl><ref type="entry">FAIRE</ref><pc>)</pc>
```

In the TEI, 2,008 references have no `target`. In SQLite, an unlinked reference has a null `resolved_entry`:

```sql
select text, target
from content_segments
where kind = 'cross_reference' and resolved_entry is null;
```

That query covers references in running text. References inside etymologies are in the `etymology` table, which has no column for a link at all (see the next section).

A missing link doesn't mean the entry is missing. In most of the examples below, the entry Littré meant is in the dictionary, and you can find it by hand.

XMLittré records each reference's target separately from the printed text, usually as the printed word in lower case (`faire` for *FAIRE*). Deep-Littré matches that target against the dictionary's headwords. A match can fail for several reasons, and only some of them are problems in the source.

### Several entries share the headword

ACIDIFIER's etymology reads *Acide et ficare, fréquentatif de facere (voy. FAIRE)*. There are two entries FAIRE: FAIRE 1, the verb, and FAIRE 2, the noun. A reader can tell that a Latin verb leads to the French verb, but the reference doesn't say which entry it means, and Deep-Littré doesn't guess.

The printed text doesn't always name the word. In ABÎME's etymology, *de même radical que bout (voy. ce mot)* means "of the same root as *bout* (see that word)". The target recorded for *ce mot* is `bout`, which is two entries, BOUT 1 and BOUT 2.

### Accents are ignored when matching

This one is a limitation of Deep-Littré, not of the source. The pipeline removes accents before it compares headwords, so to it, TACHE and TÂCHE are the same word. GERMINATIF, IVE has *Tache germinative, voy. TACHE.* The source is clear, but the pipeline sees three candidates and links none of them: TACHE ("stain"), TÂCHE 1 ("task") and TÂCHE 2 ("a kind of bale"). In the same way, ADITION's *ad, à (voy. À)* means the preposition À, but the pipeline can't tell it apart from the two entries A: the letter and the verb form.

### The headword is written differently

Some headwords give two or more spellings, joined by *ou* or *et*: DÎNER ou DÎNÉ, ADMONÉTER ou ADMONESTER, HOUACHE et HOUAICHE. The pipeline indexes such an entry only under the whole expression, so a reference to just one of the spellings doesn't match it. This is also a limitation of Deep-Littré.

You see it most in the short entries that Littré gives a second spelling, which only point to the main entry. Here is DÎNÉ in full:

```xml
<entry xml:id="dine" xml:lang="fr-x-lit19c" type="mainEntry">
	<form type="lemma"><orth>DÎNÉ</orth><pron>di-né</pron></form>
	<gramGrp>
		<gram type="pos" norm="noun">s.</gram>
		<gram type="gender" norm="masculine">m.</gram>
	</gramGrp>
	<sense xml:id="dine_s1">
		<def>Voy. <xr type="related"><ref type="entry">DÎNER 2</ref></xr>.</def>
	</sense>
</entry>
```

The entry it means is the noun DÎNER ou DÎNÉ, numbered 2 (DÎNER 1 is the verb). But `DÎNER` isn't that entry's headword, so the reference doesn't match. ADMONESTER (*Voy. ADMONÉTER.*) and AJOUTOIR (*Voy. AJUTAGE.*, whose headword is AJUTAGE ou AJUTOIR ou AJOUTOIR) fail the same way.

Ligatures cause the same kind of mismatch. A reference whose target is spelled `coeliaque` doesn't match the headword CŒLIAQUE.

### The number doesn't exist

GARDE-CHASSE has *suivant Laveaux (voy. GARDE 4)*, "according to Laveaux (see GARDE 4)". XMLittré numbers only three entries GARDE, so no entry has the number 4.

### There's no entry at all

A few references point to a word that has no entry in XMLittré. REICHSMARK reads *Le même que mark (voy. ce mot au Supplément)*, "the same as *mark* (see that word in the Supplement)", but there's no entry MARK.

### Pipeline detail

In the code, linking a reference is *resolving* it. `resolve_reference` matches a reference against the corpus and produces a raw anchor, or nothing where there's no honest answer. When a reference doesn't resolve, it has no anchor, and the compliance contract then requires a textual reference. So the TEI emits `<ref>` without `@target`, and SQLite leaves `resolved_entry` null.

The 2,008 TEI references without a target are counted with:

```
grep -o '<ref type="entry"[^>]*>' littre.tei.xml | grep -vc 'target='
```

Three kinds of failure come from the source: a bare lemma that several entries share and that the source didn't disambiguate; a homograph index that no candidate has in its `sens` attribute; and a lemma that no entry has. Two more come from the index. `fold_headword` normalizes with `stripmark = true`, so TACHE and TÂCHE, or MARCHE and MARCHÉ, collapse to one key. Even a homograph index can't separate them then, because MARCHE 1 and MARCHÉ 1 both have `sens="1"`. And a headword like `ADMONÉTER ou ADMONESTER` is indexed under the full expression rather than under each alternative. The same happens with headwords joined by *et*, and with headwords spelled with `œ` or `æ` where the reference spells the letters out. Many failures that look like "a lemma that no entry has" are actually this case.

## A reference to part of an entry links only in SQLite

Sometimes Littré points to one named section of an entry instead of the whole entry. RAVISSANT, ANTE has:

> Se dit d'un loup dressé sur ses pattes de derrière ; c'est ravir au sens de gravir (voy. RAVIR à l'étymologie).

That is, "said of a wolf standing on its hind legs; this is *ravir* in the sense of *gravir*, 'to climb' (see RAVIR, under its etymology)". XMLittré records the target as `ravir#etymologie`. SQLite links it to RAVIR's ÉTYMOLOGIE section, by giving the section's file and byte offsets:

```
kind              text    target              resolved_entry
cross_reference   RAVIR   ravir#etymologie    r.xml:1171077:1171606
```

The TEI has the same reference with no link:

```xml
<def>Se dit d'un loup dressé sur ses pattes de derrière ; c'est ravir au sens de gravir (voy. <xr type="related"><ref type="entry">RAVIR</ref></xr> à l'étymologie).</def>
```

That's because the TEI doesn't give a named section an identifier to link to. Often there's no single element that could carry one: a section's quotations are moved out to entry level, while its text stays in a `<note>`. So the TEI and SQLite count different numbers of links.

References inside an etymology have a further gap. TÂCHE 2's etymology ends *voy. TACHE à l'étymologie*. In SQLite, the `etymology` table records that reference's target, `tache#etymologie`, but it has no column for a link, so you can't follow it in SQLite. (This one wouldn't link anyway, because of the accent problem described above.)

### Pipeline detail

XMLittré calls a named section a *rubrique*, and a target like `ravir#etymologie` names one with a *fragment*: `tache#etymologie`, `indice#supplement`, `battant#historique`. These resolve to the rubrique's raw anchor, which SQLite records in `content_segments.resolved_entry`.

The TEI renderer doesn't mint an identifier for a rubrique. Under Lex-0, `<note>` can't contain `<cit>`, so a rubrique's citations are lifted to entry level while its prose stays in a note. The rubrique boundary therefore isn't expressed in TEI at all, and `target_name` finds nothing to point at. These references are emitted without a target.

Of the 43 fragment references visible in `content_segments`, 7 are unresolved. Three name a section that the entry doesn't have: DRESSANT has no rubriques, HAYON has only an ÉTYMOLOGIE, and none of the five MÔLE entries has a supplement. That's the source pointing at material that lives elsewhere, and it belongs on the upstream defects list. The rest are references whose lemma is ambiguous and whose fragment would disambiguate it, but the resolver doesn't use the fragment for that.

There are more fragment references than those 43. `etymology_row` writes a segment's printed target but no resolved columns, so a cross-reference inside an `<etym>` can't be queried in SQLite and shows up only in the TEI count.
