# Decomposition: samples and findings

Working notes on the `decomposition` pass: the samples drawn so far, what they suggest about the later characterization stage, and what is still open. The adjudication rules themselves are in [`decomposition-guidance.md`](decomposition-guidance.md).

## The pass

`decomposition` is declared but not current: it is authorable through the harness and validated against the store, but closure, scope application, and coverage do not consult it, so a decomposition record has no effect on the build. It emits `CitedForm` nodes over the `decomposition_blocks` population, which is `structural_blocks` less any block in a HISTORIQUE or ÉTYMOLOGIE rubrique. See *Pass contract* in [`../architecture/adjudication-authoring.md`](../architecture/adjudication-authoring.md).

## Two stages

Decomposition records cited forms and their glosses. A separate, later stage characterizes each form/gloss pair, and only its verdicts become pipeline constructs — a `relatedEntry`, a `homonymicEntry`, or nothing finer than the default carrier in section 16 of [`../tei-lex0-examples.md`](../tei-lex0-examples.md). Its shape is a tree rather than a sequence.

Each judgment in the tree must be a predicate on the material, not on the path. *Does the headword appear in the form?* can be answered about any node in isolation. *Does it decompose cleanly?* can only be answered inside a particular cascade, and gold authored against it dies when the cascade is re-rooted. Most of a tree is routing, which doesn't need labels; the labelling budget goes only where a person must read and decide.

The label set is not designed in advance. It's induced from what decomposition produces: a descriptive census of the accumulated nodes, grouped by gloss presence, position in the block, clause or phrase, whether the headword appears in the form, rubrique, explicit introducer, and multiple forms sharing a gloss, followed by inspection of whatever doesn't fit.

## Samples

`decomposition_development_001` was a practice run, to see whether the pass and tooling were ready. 40 items, all recorded: 16 `variante`, 9 `indent`, 15 `rubrique_indent` (8 ÉTYMOLOGIE, 5 HISTORIQUE, 1 REMARQUE, 1 PROVERBES). 12 positive, 28 negative, none unresolved. After two corrections — COUFIQUE's gloss had crossed a sentence boundary, and DISTINGUÉ's two examples became two nodes — 14 nodes, 10 glossed and 4 unglossed.

It was drawn before the population excluded HISTORIQUE and ÉTYMOLOGIE. 13 of its negatives are century markers, etymological cross-references, and language-form lists, recorded as `negative` in the sense of *no cited forms*; the exclusion stales all thirteen, which was the intent. Without them the positive rate is roughly 44%. The population version was deliberately left at 1, so 001's manifest names the same population version as later samples while its population hash differs. The remaining 27 records are still usable as development material.

`decomposition_development_002` is the first sample drawn from the current population. Ninety-nine of one hundred items were recorded: the DUCHESSE patch, applied mid-sample and confirmed against the print, shifted offsets in `d.xml`, and one later item in that file could no longer be located. Rates from this sample have denominator 99. Its gold has not yet been reviewed.

## Terminal punctuation

A form ending a sentence is recorded with its terminal period, because selection is by token. The recorded span over-reports what was meant, and downstream is not bound by it.

If the form text is a complete sentence, its terminal punctuation is part of what is quoted and stays. If the form is an isolated phrase, the terminal punctuation is a separator and is lifted to `<pc>`. One reason for this decision is corpus search, where CQL-style queries over multiword units, such as anchored patterns like `^[upos="VERB"] [lemma="un"] [upos="NOUN"]$` or length constraints, would be polluted by a trailing period. Sentence-internal separators between two constituents are lifted into `<pc>` unconditionally.

This makes *complete sentence or isolated phrase* a stage-two judgment: answerable about a node in isolation. It is the first branch of the tree to arrive from a concrete need rather than from design, and it does not track gloss presence — `Ce qui tombe dans le fossé est pour le soldat` and `La base du traité fut l'uti possidetis` are complete clauses and both are glossed.

Open: where the trim happens depends on which artifact corpus search runs over. If it runs over the TEI or the database built from it, render-time trimming suffices and the gold stays as recorded. If it runs over the adjudication spans, the trim has to reach the record.

## Numbered indents

Roughly 1,463 `<indent>` elements begin with a digit and a period, 459 of them sequence starts, concentrated in REMARQUE with SYNONYME and SUPPLÉMENT AU DICTIONNAIRE also represented. The enumerator renders as `@n` on the `<sense>`, with its trailing period dropped as formatting.

Lifting it out of the projected target, as `semantique/domaine` markers already are, would stop sentence segmenters splitting after `1.` and stop the adjudicator leaving a one-token residual on every numbered indent, as DISPUTER did. It is deferred: it changes the projection text, requires rebuilding the segment map that anchors projected spans to source offsets, and changes the surface hash of every numbered indent, and its main benefit only matters once something automated segments.

The counts in the original survey (457 against 459 sequence starts, 371 REMARQUE against 386 by XPath) are consistent with nested rubriques, since the survey assigned the nearest preceding rubrique while `ancestor::` matches any.

## Observed families

Families seen so far, worth enriching a challenge sample for: elliptical coordination (LIVRE, TIRER); framing formulas of both kinds (CHEVROTER, LIVRE, TIRER against ENLEVER, TIQUEUR); prescriptive remarks (AMBITION); a definition followed by trailing examples (DISTINGUÉ, CHEVROTER); multiple forms sharing a gloss (RENVERSÉ); translation equivalents (UTI POSSIDETIS); pronominals (RETREMPER); residuals with an antecedent outside the block (MORELLE, AMBITION). Challenge accuracy is a stress-test statistic only.

## Next

1. Review the 002 gold.
2. Census the nodes of 001 and 002 together.
3. Induce the stage-two tree from that census.
4. If time allows, a challenge sample enriched for the families above.
