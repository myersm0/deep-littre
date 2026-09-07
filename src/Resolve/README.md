# Resolve

The only place that decides what the corpus means. It combines deterministic facts recovered from explicit source markup with judgments read from the adjudication store, and produces the immutable representation that both renderers consume.

Explicit facts are reconstructed every build from source, code, and the committed normalization tables; they are not judgments and do not occupy the store. Judgments come from the store and carry provenance. Deleting the store must still yield a coarse corpus carrying every explicit XMLittré fact.

This module also owns every derivation that must be identical across outputs. Both renderers must agree and neither may infer, so anything a renderer would otherwise work out — a century's machine-readable range, a citation's rubrique subtype, an `ID.` citation's resolved author, and `ID.`/`ib.` antecedent links — is carried from here.

The semantic model itself is specified in `docs/architecture/semantic-model.md`; closure and scope application are stated in `docs/architecture/adjudication-rendering.md`. This file covers how the code is arranged and where the non-obvious decisions sit.

## Files

`representation.jl` holds the resolved types and the closed `finding_categories` set. `derive.jl` is the resolution proper. `norms.jl` routes printed labels to normalized qualification targets. `inline.jl` assembles ordered inline content. `references.jl` builds the headword index and resolves cross-reference targets. `etymology.jl` segments etymology rubriques.

## Closure

`closure` requires the block to be eligible for every structural alternative, every alternative to have an applicable verdict that decided one way or the other, and the resulting assertions to be structurally compatible. Positive structural partitions are validated by the harness at authoring time and revalidated when persisted records are materialized: a positive exhaustive record must account for every source-visible projected character through node spans or residual spans before it enters runtime resolution.

Any unmet condition leaves the semantic type underdetermined. Only conditions indicating a defective claim become review findings. A block nobody has examined is the ordinary intermediate state, not a finding. A block every structural pass has examined and one has left `unresolved` is a finding — the one case where the model cannot otherwise tell examined-and-undecided from unexamined.

A derived `Sense` spans its enclosing block rather than its direct content. After carving out asserted structural children the direct content is discontinuous and no single interval represents it, whereas a parent extent containing its descendants is the ordinary reading of a source-anchored tree. So `prose A [SubLemma] prose B` resolves to one contiguous `Sense` containing the sub-lemma, with both stretches of prose supplying the definition, which is also what Lex-0's nesting of `<entry type="relatedEntry">` inside `<sense>` requires.

## Parentage is geometry

Among containing structural nodes, the smallest strict containing span is the parent. A qualification marker or citation lying inside an asserted node belongs to that node rather than to the block enclosing it. A marker outside every node stays where the source put it.

An adjudicated scope overrides that geometry and nothing else. It moves where a marker applies, never what it means: the full set of qualification facts is byte-identical before and after a scope record is applied.

Coincident spans for distinct nodes, and partial crossing overlap, are structural conflicts. They are withheld from the resolved tree and reported rather than resolved by precedence.

## Label routing

Nothing in `norms.jl` is an adjudication. It routes qualification text through three committed tables in `data/`. For explicit `<semantique>` and `<nature>` markup the source supplies the marker boundary directly; for bare prose the `bare_qualification` pass supplies only that boundary and its scope. In both cases the semantic target is reconstructed deterministically here.

Routing is tiered: exact match, then prefix rules, then lemma rules, with a discourse-tail retry only after every tier has missed, so no previously routed atom can change target. `route_spans` tries a whole-string POS parse first, so `s. m. et f.` stays one reading instead of splitting on the connector, and each target travels with the printed span it was routed from.

The three tables are declared with `include_dependency`. Without it, editing a table would not invalidate the precompile cache and the package would silently serve stale routing.

## Cross-references

Littré writes a cross-reference as a lemma, optionally with a homograph index and a fragment: `abject`, `avoir.1`, `zéro#var2`, `faux.1#var26`, `tache#etymologie`. A homograph index names the entry whose `sens` attribute carries that number rather than an ordinal in document order. A fragment names either a variante of the target entry or one of its named rubriques.

Resolution produces a raw anchor, not a rendered identifier, since `xml:id` values belong to the TEI renderer and SQLite keys on anchors. `select_target` tries exact-headword candidates before lemma candidates — `MI` is a headword in its own right while `abject` is only the lemma of `ABJECT, ECTE` — and falls back to the lemma set whenever the narrower one answers nothing, so `garde.4` still reaches `GARDE, ÉE`.

`fold_rubrique` states the correspondence between a printed fragment and a `@nom` as a rule rather than an enumeration: fragments are lowercase, unaccented and sometimes pluralised, so `#supplement` names `SUPPLÉMENT AU DICTIONNAIRE` and `#proverbes` names both `PROVERBE` and `PROVERBES`.

An unresolvable reference carries no anchor. The compliance contract then requires a textual reference, so the TEI emits `<ref>` without `@target`. See `docs/known-limitations.md` for the measured residue.

## Rubriques

Rubrique conventions live in code rather than in adjudication records: `cit/@subtype`, `lbl/@type` and `note/@type` are project convention, since Lex-0 leaves them unconstrained. They are policed at the output — citation and note values come from the committed rubrique table, label values are the committed `dateRange` and `supplement` constants.

HISTORIQUE does not fold into `<etym>`. Folding merges two distinct source rubriques, and an entry with two `ÉTYMOLOGIE` rubriques (COTRET) has no principled choice of which to fold into. Attestations serialize at entry level, parallel to `<etym>`, with `cit/@subtype="attestation"`.

HISTORIQUE lead text has a small deterministic grammar: a century token and `Ajoutez :` may occur in either order, with either absent. The century becomes `dateRange`, the supplement marker becomes `supplement`, and remaining inline material stays prose. Lead text matching neither marker becomes a `century_unrecognized` finding. `century_years` parses the roman numeral to a `notBefore`/`notAfter` range here and `carry_date_range` attaches it to each following citation, stopping at the next header.

## Etymology

`etymology.jl` is ported from the v0.2 `etym.jl`, which remains the calibrated reference: tokenizer, cluster grammar, gloss extraction, rescue path and suspect heuristic are unchanged, because they were tuned against the full corpus and re-deriving them would silently change verdicts. Two things differ. Segments no longer build markup strings, which is now the renderer's business; and segments whose position is known carry a raw anchor threaded from the event range, while connectors and prose are located by their block.

This is deterministic enrichment, not adjudication. It is reconstructed every build from source plus the committed language table, and its suspect residue is a generated review finding rather than a stored judgment.

Segmentation keys on Gannaz's italic and anchor markup, so an etymology carrying neither falls back to a single prose segment indistinguishable in the output from one the segmenter read and found to be prose. `EtymProse` therefore carries why the fallback fired, and `resolve` turns that into an `etymology_unsegmented` finding beside `etymology_suspect`. That count is what lets etymology coverage be quoted against a real denominator.
