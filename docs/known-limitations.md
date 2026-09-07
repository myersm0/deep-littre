# Known limitations

The four limitations listed in the root README, stated in the pipeline's own terms with the measurement behind each. Figures are from the current build unless noted; the scripts named beside them regenerate the numbers.

## Entete markup is flattened into header notes

`entry_header` emits the entete material that is neither the entry's pronunciation nor a label qualifying it as `<note type="header">`, one note per contiguous run. Loose text, an `<indent>`, a cross-reference, and the pronunciation and label of a further headword form all belong to the run they sit in; a run printing no letter or digit is just separator punctuation, it doesn't carry anything.

The note does not carry the type of a `<semantique>` inside it. `inline_from` builds the note through `gather_node!`, which has no branch for `<semantique>` and so recurses and absorbs the text. The printed label survives; the fact that Gannaz typed it does not.

Measured by `bin/entete_report.jl`: 99 `<semantique>` elements sit inside an entete, 90 opening an `<indent>` and 9 as direct children of `<entete>`, with none elsewhere inside a block. 92 carry `type="domaine"`, 4 `type="indicateur"`, 3 are untyped. In any other position the same element is carved out by `route_spans` and re-emitted as a `<usg>` carrying its type, so the entete is the one place the pipeline drops a type the source states.

Recording it would mean a `<seg type="…">` inside the note, since the pinned RNG gives `<note>` `macro.lexSpecialPara`, which admits `model.segLike` and not `<usg>`. Deferred: the mechanism costs a field on `Emphasis`, a flag on `InlineBuilder`, and two new branches, against 92 labels, and nothing downstream consumes the type today — header notes reach SQLite as flattened text and emit no `content_segments`.

## Entry-level natures that no norm table routes

An entry-level `<nature>` reaches `route_spans`, which tries a whole-string POS parse, then routes each atom through the agreement, construction, POS and register tables in turn. An atom that no tier claims falls through to `UsgTarget("hint", "")` and is emitted as `<usg type="hint">` scoped over the entry.

Measured by `bin/nature_report.jl` over every `<nature>` in the corpus: 124 unrouted atoms, 105 distinct, across 117 entries. 121 are entete natures reaching `entry_grammar`; 3 are inline in a block. There is no sense-level population — a row added for these clears the entete and nothing else.

The residue divides three ways.

**Table gaps.** Spellings of parts of speech the tables already carry under another form. The W3 rows in `data/pos_abbreviations.toml` and `data/usg_register_norms.toml` close 13 of these. Two measured gaps are deliberately still open: `p.` for a participle and `r.` for a reflexive are single-letter tokens too generic to claim across every `<nature>` for one entry each.

**Grammatical prose.** Real grammatical content stated as a sentence — `pluriel de AIL.`, `impér. de tenir.`, `part. passé invariable d'appartenir`, `3e pers. sing. ind. prés. du verbe AVOIR.`. `de` alone blocks 43 of the 124 and no table row touches any of them, because the atom is a construction rather than a label. For this group `<usg type="hint">` scoped over the entry over-claims: `pluriel de AIL.` is not a usage label and does not scope over anything. The classification campaign is what reduces this residue.

**Fused label and commentary.** `s. f. (mais d'après les botanistes, s. m)`, `s. f. d'après l'Académie, mais s. m. d'après l'usage des lieux où croît cet arbre`, and F's two pronunciation notes. The header of `usg_gram_norms.toml` already names this family as `split_bare_transition` residue.

Six entries read `part passé` with the period missing after `part`, which is an XMLittré typo and belongs on the list of upstream defects to report alongside `BARDÉ, ÉÉ` and `COUCHEUR. EUSE`.

## Unresolved cross-references

`resolve_reference` matches a reference against the corpus and produces a raw anchor, or nothing where no honest answer exists. A reference that does not resolve carries no anchor, and the compliance contract then requires a textual reference, so the TEI emits `<ref>` without `@target` and SQLite leaves `resolved_entry` null.

2,008 reference occurrences in TEI carry no target, counted as:

```
grep -o '<ref type="entry"[^>]*>' littre.tei.xml | grep -vc 'target='
```

The unresolved cases are bare lemmas shared by several entries that the source declined to disambiguate; homograph indices no candidate entry carries in its `sens` attribute; and lemmas no entry carries at all. A further class is a consequence of the index: `fold_headword` normalizes with `stripmark = true`, so MARCHE and MARCHÉ collapse to one key and a homograph index that would separate them cannot. Headwords like `ADMONÉTER ou ADMONESTER` are indexed under the full expression rather than under each alternative.

## References naming a section of an entry

A reference may carry a fragment naming one of the target entry's rubriques — `tache#etymologie`, `indice#supplement`, `battant#historique`. These resolve to the rubrique's raw anchor, which SQLite records in `content_segments.resolved_entry`.

The TEI renderer doesn't mint an identifier for a rubrique. `<note>` can't hold `<cit>` under Lex-0, so a rubrique's citations are lifted to entry level while its prose stays in a note; the rubrique boundary is therefore not expressed in TEI at all, and `target_name` finds nothing to point at. Those references are emitted without a target, so the SQLite and TEI resolution figures do not agree.

Of the 43 fragment references visible in `content_segments`, 7 are unresolved. Three name a section the entry does not have — DRESSANT carries no rubriques, HAYON only an ÉTYMOLOGIE, and none of the five MÔLE entries a supplement — which is the source pointing at material that lives elsewhere, and belongs on the upstream defects list. The rest are references whose lemma is ambiguous and whose fragment would disambiguate it, though the resolver does not use it for that.

That population is larger than 43: `etymology_row` writes a segment's printed target but no resolved columns, so a cross-reference inside an `<etym>` is unqueryable in SQLite and appears only in the TEI count.
