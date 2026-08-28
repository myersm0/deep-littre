# v0.3 rewrite disposition

Status: **normative implementation plan**.

## Decision

v0.3 is a clean-slate rewrite of the pipeline core inside the existing `deep-littre` repository.

The repository, release history, calibrated data, source patches, validation infrastructure, adjudications, and accumulated Lex-0 research are preserved. The v0.2 internal ontology and mutation-based pipeline are not migration constraints.

The reason is architectural rather than stylistic. v0.2 models a source `<indent>` through one mutually exclusive `IndentRole`, then mutates and reparents model objects as enrichment proceeds. The v0.3 semantic model instead permits one source block to yield zero, one, or many semantic nodes plus independent qualifications and relations, all anchored to source spans. TEI nesting is derived from those facts rather than produced by destructive transformation of the source model.

No dual v0.2/v0.3 pipeline is maintained on `main`. v0.2 remains runnable from its release tag and Git history.

## Preserve, salvage, rewrite

### Preserve as authoritative inputs or external contracts

- the original XMLittré source;
- `patches.toml` and patch provenance;
- calibrated usage/grammar normalization tables;
- the etymology language table;
- existing hand/LLM adjudication data where such durable judgments actually exist, migrated only after the new record shape has been exercised end to end;
- historically tagged/labeled locution artifacts retained for provenance review, not presumed to be adjudicated ground truth;
- the pinned TEI Lex-0 schema and `jing` validation harness;
- the probe corpus and expected verdicts;
- the 25-entry development corpus (`test/corpus`) and useful golden fixtures;
- v0.2 releases as a semantic-preservation oracle.

### Salvage conceptually and, where clean, substantially in code

- label routing in `norms.jl`, which already produces multiple orthogonal typed atoms from one source label;
- the etymology event/segment model in `etym.jl`, which is independent of `IndentRole`;
- author-resolution logic and other transformations that do not depend on the old role ontology.

Salvage is by inspection, not by obligation. New modules should not inherit old APIs merely to maximize code reuse.

### Rewrite

- the source model and parser integration;
- indent classification and locution/proverb extraction;
- scope handling and destructive reparenting;
- review-flag machinery that encodes old role assumptions;
- both renderers' interfaces to the model;
- the generated SQLite schema;
- most tests that assert `IndentRole`, `TransitionGroup`, heuristic classification, or old `sense_type` behavior.

## Disposition of the previous v0.3 migration cut

The semantic conclusions of the span-anchored schema revision survive. Migration scaffolding whose only purpose was to make in-place surgery safe does not.

### Cancelled with the old architecture

- the exhaustiveness test over the three `IndentRole` enumeration sites;
- deleting the old `sense_type_for(::IndentRole)` catch-all as a migration prerequisite;
- reconciling v0.2 `nothing` handling between emitters;
- other tests whose only job was to keep the role-based readers synchronized while that hierarchy was being dismantled.

The underlying principle survives: every successor enumeration or closed union must fail loudly when unhandled, and the two renderers must be checked against the same semantic facts.

### Still required because it hardens the source substrate

Before large-scale adjudications are committed:

- require each patch's `old` text to begin exactly once on its configured source line;
- allow replacements to change byte length and line count, with coordinate drift carried by the transform map;
- audit each normalization rule against the full corpus rather than carrying it forward by inertia;
- verify source encoding/newline/BOM assumptions used by the span layer;
- freeze the classifier-facing projection and stale-verdict contract before producing expensive verdicts.

The Latin `<span lang="la">` normalization should not retain a cross-line `s`-flag merely for compatibility. First inventory the full corpus; if no legitimate multiline instance exists, constrain the rewrite to the actual syntax and preserve the line-local invariant.

The `xml:space="preserve"` injection from v0.2 must likewise be re-justified under XML.jl 0.4.x, which preserves inter-element whitespace by default. Remove it if the new renderer no longer needs it.

## Documentation reconciliation

The July TEI compliance notes and worked examples are preserved as research but are not copied forward verbatim. They predate later probe results and the schema revision.

The rewritten `tei-lex0-compliance.md` and `tei-lex0-examples.md` are normative summaries reconciled against:

1. the pinned RNG and probe verdicts;
2. schema-valid v0.2 output;
3. the v0.3 semantic model.

Known July-era recommendations that are explicitly superseded include `<dictScrap>` and direct `<date>` inside `<etym>`, neither of which is admitted by the pinned RNG.

## Development sequence

### 1. Freeze v0.2

Tag the final v0.2 state. Historical implementation documentation remains available from that tag. On the v0.3 branch, do not keep a legacy pipeline beside the rewrite.

### 2. Harden source transforms

Land the patch guards and source invariants first. Establish the XML.jl 0.4.x source API and exact dependency pin before adjudication anchors exist.

### 3. Build the source layer and census

Implement the source representation independently of semantic adjudication. In week one, benchmark full-corpus `FlatNode` parse, traversal, and span extraction with the exact pinned XML.jl version; `LazyNode` is a correctness/reference fallback, not the corpus-scale execution plan. Run the full-corpus parse-and-`SourceBlock`-census smoke test early; parser and source-vocabulary edge cases are expected in the 78,599-entry tail, not necessarily in the 25-entry sample.

### 4. Build the adjudication authoring path and exercise it on development inputs

The primary fast loop is:

- the 25-entry sample;
- the Lex-0 probe corpus;
- selected golden fixtures that capture important v0.2 preservation behavior.

Before structural coverage work scales up, implement the versioned adjudication projection and authoring harness so a human, LLM, or rule pass can return semantic decisions without authoring source coordinates or hashes. Then implement at least two thin structural adjudication passes:

- `SubLemma`;
- `VoiceVariant`.

For v0.3, the current structural alternatives are:

- `SubLemma`;
- `VoiceVariant`.

A block is derivable as an ordinary `Sense` only after every current structural pass has an applicable non-unresolved verdict and the resulting assertions are structurally compatible. Positive structural passes perform exhaustive extraction over their projected target and expose explicit residual spans; the authoring/application path verifies that node plus residual spans account for the full target.

### 5. Validate one complete adjudication path

Before importing any legacy classification artifact or settled ruling, demonstrate on real sample material:

`source block → classification surface → examination record → projected assertion → materialized runtime span → semantic resolution → TEI → SQLite`

The point is to discover record-shape mistakes before the most expensive hand-made data is converted.

### 6. Review and import existing adjudications deliberately

There is no assumed legacy verdicts CSV population to migrate. Audit provenance before treating any historical locution tag/label artifact as an adjudication; the reported population is retained for review and may later become an evaluation asset if its quality warrants it, but it is not ground truth by default.

Only judgments whose provenance establishes that they are actual settled human/LLM/rule adjudications are imported into the authoritative store. Settled cabinet rulings and similar cases can be imported after the end-to-end path above is stable; unverified legacy tags remain reference/audit data rather than authoritative records.

## Retirement gate for v0.2 code

The 25-entry sample is a development corpus, not a deletion gate.

The old implementation may be removed from `main` only after the new pipeline satisfies all of the following:

1. the full XMLittré corpus parses successfully;
2. the full `SourceBlock` census completes and its invariants hold;
3. all 78,599 entries render through the new pipeline;
4. the whole TEI document and every entry validate against the pinned RNG;
5. a canonical semantic-preservation extraction agrees with v0.2 for facts expected to survive;
6. every remaining difference is on an explicit allowlist of intended v0.3 changes;
7. SQLite integrity and TEI/SQLite cross-output invariants pass.

The preservation comparison should compare facts, not raw XML layout. At minimum it should inventory entry identity/headwords, pronunciations, grammatical facts, definition text, citations and attribution, rubrique content, etymological content/events, supplements, and cross-references. Expected v0.3 differences include the removal of workflow-state annotations, adjudication-driven sub-lemma/voice structure, and any documented correction required by the pinned schema.

## Release-facing breaks

v0.3 is allowed to break v0.2 query surfaces whose meaning depended on the old ontology. In particular:

- `ana="unclassified"` is removed from published TEI;
- the old SQLite `senses.role` / `sense_type` vocabulary is not preserved as an architectural constraint;
- published `xml:id` stability across pre-1.0 releases is not promised unless a later decision explicitly introduces such a promise.

The preservation comparison against v0.2 will therefore surface differences that are intended
rather than defects. The allowlist of expected divergences:

- **`HISTORIQUE` no longer folds into `<etym>`.** v0.2 nested historical attestations inside the
  etymology; v0.3 serializes them at entry level, structurally parallel to `<etym>`. This is a
  fidelity decision — folding merges two distinct source rubriques, and an entry with two
  `ÉTYMOLOGIE` rubriques (COTRET) has no principled choice of which to fold into. The v0.2 shape
  also placed `<date>` beside `<cit>` inside `<etym>`, which the pinned RNG does not admit.
- **`ana="attestation"` becomes `cit/@subtype="attestation"`.** `@ana` is narrowed to epistemic
  provenance, with a whitelist test admitting only `resolved` and `suspect`.
- **Rubrique citations appear that v0.2 dropped entirely.** `<note>` cannot hold `<cit>`, so v0.2's
  `<note type="historical"><seg>` rendering destroyed every rubrique citation — 261 of the
  development corpus's 818, with their authors and references, reached neither output. Citation
  counts rising is the fix, not a regression.
- **Sense and definition counts rise** because rubrique structure is emitted rather than swallowed.
- **Print casing is preserved** in grammatical atoms where v0.2 lowercased it.
- **Inline structure is queryable in SQLite** through `content_segments`; v0.2 flattened
  cross-reference targets and source wrappers into plain text.

These changes require release notes and matching README/query-documentation updates.
