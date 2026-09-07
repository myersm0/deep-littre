# Census

Which source blocks exist for adjudication. Walks the patched parser view, runs before any semantic work, and depends on nothing semantic.

`docs/architecture/overview.md` introduces blocks and kinds; `docs/architecture/semantic-model.md` states the population contract. This file is about the traversal and the reasons behind each kind.

## Structure

`census(document)` produces a `DocumentCensus` of `SourceEntry` objects, each holding ordered `SourceBlock`s and `SourceRubrique`s. `census(documents)` produces the `CorpusCensus`.

Blocks nest, so `all_blocks` flattens depth-first in source order. That ordering is what `population_hash` depends on, so it is not free to change.

Rubriques are addressable source objects with their own spans, since a qualification or relation may target a rubrique rather than a block.

Kinds are singleton types rather than an enumeration, so an unhandled kind raises at the dispatch site instead of falling through a branch. `block_kind` errors on an unknown element name for the same reason.

## The nine kinds

`indent`, `variante`, `resume_indent`, `resume_variante`, `rubrique_indent`, `rubrique_variante`, `rubrique_direct`, `entete_indent`, `entete_nature`.

Kind is decided by walking ancestry, not by element name. The résumé and rubrique kinds are separate kinds rather than flags on `indent` and `variante`, which makes accidental inclusion in a pass population harder to write.

`rubrique_direct` names direct rubrique prose with no intervening `<indent>` or `<variante>`. Without it that material would not exist as an adjudication target.

Résumé ancestry is consulted for `<indent>` and `<variante>` alike. FAIRE, LAISSER and PRENDRE each put an `<indent>` directly inside `<résumé>`; PRENDRE's carries a `<semantique>` marker and is otherwise indistinguishable from a real sense, and only its ancestry identifies it as a summary of senses represented elsewhere in the entry. Résumé material is excluded from the structural population for that reason.

A `<nature>` appearing inline inside an eligible block is not a block of its own. It is markup within one, and may become a grammatical qualification marker — as in DISPENSER variante 7, `Se dispenser, <nature>v. réfl.</nature> Être départi.`, where the whole variante is the block and the `<nature>` is a marker inside it. Only `<nature>` directly under `<entete>` is a block, of kind `entete_nature`.

`<entete>` is walked like any other container rather than being read for `<nature>` alone. Its `<nature>` children become `entete_nature` and its `<indent>` children `entete_indent`.

## Why the entete kinds sit outside both populations

`entete_indent` is a kind of its own because the 321 blocks it names are not sense material: 227 are editorial prose, 90 open with a `<semantique>` label, and none contains a `<variante>`. As ordinary indents they entered the structural population, where the sense-subdividing passes would be asked to find senses in an entry note, and the TEI renderer emitted each one as a `<sense>` with no definition. They reach the renderers as entry header notes instead. A further 9 `<semantique>` elements sit directly under `<entete>` outside any `<indent>`, so they are not census blocks at all and reach `entry_header` as loose material.

Exclusion from the *qualification* population needs a separate reason, since a share of those 321 read like qualifications and `qualification_scope` is the pass that would decide what such a label covers. Two mechanical facts settle it, neither a judgement about the material.

No verdict would be consumed. `resolve_entry` filters both entete kinds out of block resolution, and the entete is handled by `entry_header`, which walks the source directly and consults no adjudication record.

The verdict could not be stated in any case. A `ScopeAssertion` target is a projected span inside the examined block; the `block_text` projection excludes descendant blocks; and `attaches_to` requires a resolved node whose span covers the scope span. No sense node covers anything inside `<entete>`, so "this label covers the entry's senses" has no representation. See `docs/architecture/semantic-model.md`, *Scope and target references*, for the target vocabulary this is a gap in.

Admitting either kind therefore means building a consumer path and an entry-level scope target, not relaxing a predicate.

## The population hash

`population_hash` runs over the ordered current source anchors and kind names rather than over a count, so a changed denominator cannot present itself as the same population under an unchanged total. It identifies a coverage population and is not adjudication-record identity.

Any change to census kinds or population membership therefore changes the reported coverage population. Existing verdicts survive it; applicability is decided independently by pass eligibility and version, and by each record's classification surface.

## Sizes

The full corpus censuses 421,970 blocks across 78,599 entries. The structural and qualification populations are both 341,125 blocks: ordinary indents and variantes plus the three rubrique kinds.
