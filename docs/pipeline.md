# Pipeline behavior

This document specifies the observable behavior of each pipeline phase, current as of v0.2.0 (the TEI Lex-0 conformance release).

Entry point: `run_pipeline.jl` calls `parse_all` → `enrich!` → `scope_all!` → `collect_flags` → `emit_tei` / `emit_sqlite`.

## Architecture: two emitters, one model

The TEI emitter and the SQLite emitter are two independent interpreters of the shared model (`Vector{Entry}`), and `collect_flags` (`flags.jl`) is a separate model-only pass. A decision made inline in either emitter is invisible to the other and has no channel into `review_queue`. This yields the project's **transform placement principle**: any transform that must route uncertain cases to review, or that changes what SQLite's `sense_type`/`role` ought to be, belongs in the model layer (`model.jl`/`enrich.jl`/`scope.jl`), where both emitters and the flag pass see it; transforms that are pure serialization concerns live in `emit_tei.jl`.

Shared data — the language table (`data/etym_language_table.toml`), the usg norm tables (`data/usg_register_norms.toml`, `data/usg_gram_norms.toml`), and the POS abbreviation table — lives in committed TOML files readable by both layers, never inline in an emitter. The shared routing layer (`src/norms.jl`) returns typed atoms and lets callers place them: a single source label like `absolument et familièrement` yields a `<gram type="construction">` for a `<gramGrp>` and a separate `<usg type="socioCultural">`. All label routing goes through this router; parallel routing paths are a defect.

Where a position-sensitive detection feeds both a review flag and an emission decision (the etymology suspect channel), the detection logic exists exactly once, called on the same model-layer string by both consumers, so corpus counts and flag counts agree by construction.

## Phase 1: Parse

**Input**: A directory of Gannaz XML files (`a.xml`–`z.xml`, `a_prep.xml`), and optionally a patches TOML file.

**Output**: `Vector{Entry}` with all structural information extracted but no enrichment applied. Every `Indent` has a `SourceLocation`; all `classification` fields are `nothing`; all `resolved_author` fields are empty; all `canonical_form` fields are empty.

### 1a. Patches

Patches are loaded from a TOML file as an array of `{file, line, old, new}` records. For each file, applicable patches are filtered by filename and applied in order to the raw text before XML parsing. Each patch does a single `replace(...; count=1)` on the specified line. If the `old` string is not found on that line, the pipeline errors.

**Invariant**: patches never add or remove lines. Source line numbers are stable across patched and unpatched text.

### 1b. Source normalization

Applied to raw text after patches, before XML parsing:

1. Add `xml:space="preserve"` to the root `<xmlittre` tag.
2. Normalize rubrique names: `PROVERBE` → `PROVERBES`, `REMARQUES` → `REMARQUE`.
3. Convert `<span lang="la">...</span>` to `<i lang="la">...</i>`.

### 1c. Indent line tracking

XML.jl does not expose source line numbers. The pipeline pre-scans the raw text for `<indent` opening tags and records their line numbers in document order. During DOM traversal, each `parse_indent` call consumes the next line number from this queue. The scan and the DOM parse both visit indents in document order, so the two stay in sync.

Note: the pipeline pins XML.jl to the 0.3.x line (`Project.toml` compat). XML.jl 0.4.0 is a breaking rewrite that preserves whitespace text nodes, silently changing `doc[end]` root-node access and causing every source file to parse to zero entries.

### 1d. Content extraction

`extract_content` walks an element's children and separates them into:

- **Inline content**: text nodes and non-structural element children, serialized back to markup via `XML.write`. Joined and whitespace-collapsed into a single string.
- **Structural children**: `<cit>` → `Citation`, `<indent>` → `Indent` (recursive), `<rubrique>` → `Rubrique`, `<variante>` → `Sense`.

The structural tag set is `{cit, indent, rubrique, variante}`. Everything else (e.g. `<semantique>`, `<nature>`, `<exemple>`, `<a>`, `<i>`) is treated as inline markup and preserved in the content string.

### 1e. Citation parsing

Each `<cit>` element produces a `Citation` with:

- `text`: full inner content (text + inline markup), stripped of leading/trailing whitespace.
- `author`: from the `aut` attribute (empty string if absent).
- `reference`: from the `ref` attribute.
- `hide`: from the `hide` attribute.

### 1f. Entry parsing

For each `<entree>` element:

- `headword` from the `terme` attribute.
- `homograph_index` from the `sens` attribute (parsed as `Int`, or `nothing` if absent).
- `is_supplement` is true when `supplement="1"`.
- `pronunciation` and `pos` extracted from `<entete>/<prononciation>` and `<entete>/<nature>` respectively, using only the leading text content (not nested elements).
- Body senses: all `<variante>` children of `<corps>`, in document order.
- Rubriques inside `<corps>`: each `<rubrique>` yields a `Rubrique` plus zero or more supplement `Sense`s (from `<variante>` children of the rubrique).
- Rubriques at entry level (direct children of `<entree>`): same treatment as corps rubriques.
- `resume_text`: raw XML serialization of the `<résumé>` element, if present.
- Supplement senses (from rubriques) are appended to the body after regular senses, with `is_supplement=true`.

### 1g. Sense parsing

Each `<variante>` element produces a `Sense` with:

- `num` from the `num` attribute (parsed as `Int`, or `nothing`).
- `is_resume` is true when `option="résumé"`.
- Content, citations, indents, and rubriques via `extract_content`.

### 1h. Rubrique parsing

Each `<rubrique>` element produces a `Rubrique` with:

- `kind` looked up from the `nom` attribute. Known values: `HISTORIQUE`, `ÉTYMOLOGIE`, `REMARQUE`/`REMARQUES`, `SYNONYME`, `PROVERBES`/`PROVERBE`, `SUPPLÉMENT AU DICTIONNAIRE`. Unknown values log a warning and default to `Remarque`.
- Content, citations, and indents via `extract_content`.

Any `<variante>` children inside the rubrique are returned separately as supplement senses.

### 1i. ID generation

`make_id(headword, homograph_index)`:

1. NFKD-normalize, lowercase.
2. Strip all non-ASCII characters.
3. Replace all non-alphanumeric characters with `_`.
4. Collapse consecutive `_` to one.
5. Strip leading and trailing `_`.
6. If empty or doesn't start with a letter, prepend `e_`.
7. If `homograph_index` is not nothing, append `.N`.

Examples: `DÉGOÛTÉ, ÉE` → `degoute_ee`. `À` → `a`. `-ESQUE` → `e_esque`.

### 1j. ID deduplication

Deduplication runs twice: once per file (on `parse_file` return), and once globally (on `parse_all` return).

For any ID that appears more than once, all occurrences receive a `_N` suffix in encounter order: `degout_1`, `degout_2`, etc. Entries with unique IDs are left unchanged.

Deduplication mutates `entry.id` (a `Ref{String}`) in place.

## Phase 2: Author resolution

**Input/output**: mutates `Citation.resolved_author` in place across all entries.

For each entry, citations are collected in document order by walking: body elements (senses only) → sense citations → sense indents (recursive) → sense rubriques → then entry-level rubriques.

A running `last_author` variable (initially empty) tracks the most recent named author:

- If `author == "ID."` and `last_author` is non-empty: `resolved_author = last_author`.
- If `author` is non-empty and not `"ID."`: update `last_author`, set `resolved_author = author`.
- Otherwise: `resolved_author = author` (preserving whatever it was, including empty).

Author resolution is scoped to each entry independently. The `last_author` resets at entry boundaries.

**Edge case**: an `"ID."` citation with no preceding named author in the same entry gets `resolved_author = ""`.

## Phase 3: Indent classification

**Input/output**: mutates `Indent.classification` in place. After this phase, every indent has a non-null classification — either to a real role or to `Unclassified`.

Classification is recursive: after classifying a parent indent, all of its children are classified.

The classifier follows a **certain-or-Unclassified** regime: rules either match enough structural signal to be definitively right, or the indent is left `Unclassified` for downstream review. There is no confidence axis. Three tiers are tried in order; the first to succeed wins.

### Tier 0: Verdicts (external overrides)

Loaded from a CSV keyed on `(file, line)`. Columns: `file`, `line`, `check` (optional), `heuristic_role`, `llm_role`. The `llm_role` column is used; `heuristic_role` is informational. An `llm_confidence` column is tolerated if present (legacy schema) but ignored — confidence is no longer part of the model.

If a verdict exists for the indent's source location:

- If a `check` value is present and the indent's plain-text content does not start with it, the verdict is rejected with a warning.
- Otherwise, the indent is classified with the verdict's role and method `LlmAssisted`.

### Tier A: Deterministic (tag-based)

Operates on the raw markup content string (not stripped of tags):

| Condition | Role |
|-----------|------|
| Contains `<semantique type="indicateur">Fig.` | Figurative |
| Contains `<semantique type="domaine">` | DomainLabel |
| Contains `<nature>` | NatureLabel |
| Contains `<exemple>`, plain text starts with a proverb marker (`Prov.`, `Proverbe`, `Proverbialement`) | Proverb |
| Contains `<exemple>` (otherwise) | Locution |
| Contains `<a ref=`, plain text < 120 chars, starts with `voy.`/`V.`/`Voy.`/`voyez` (case-insensitive) | CrossReference |
| Contains `<a ref=`, plain text < 120 chars, ends with `, voy.` | CrossReference |

The checks are tried in this order; first match wins.

**Important**: the presence of `<nature>` takes precedence over any heuristic interpretation of the inner text. For example, `<nature>Substantivement.</nature>` is always classified as NatureLabel, even though the plain text `Substantivement.` would otherwise match the VoiceTransition heuristic.

### Tier B: Heuristic (text patterns)

Operates on plain-text (stripped) content. Patterns are organized as `Vector{Regex}` per role with anchored, word-boundary-enforcing patterns. Rules either match definitively or fall through.

| Condition (on plain text) | Role |
|---------------------------|------|
| Starts with proverb marker (`Prov.`, `Proverbe`, `Proverbialement`) | Proverb |
| Starts with register label (`Populaire(ment)?`, `Familièrement`, `Vulgairement`, `Par extension`, `Par analogie`, `Néologisme`, `Il est familier`, `Mot vieilli`, etc.) | RegisterLabel |
| Starts with voice/grammatical transition (`V. n`, `V. a`, `V. réfl`, `Se conjugue`, `Absolument`, `Substantivement`, `Adverbialement`, etc.) | VoiceTransition |
| Starts with `Fig.` followed by whitespace | Figurative |
| Standalone label `Au pluriel`, `Au féminin`, `Au singulier`, `Au masc(ulin)?`, `Au fém(inin)?`, `Avec un nom de …` (entire indent is the label) | VoiceTransition |
| Standalone bare register token (`Vieux`, `Vieilli(e)?`, `Bas(se)?`, `Vulgaire`, `Triviale?`, `Inusité(e)?`, `Familièr(e)?`, etc.) — entire indent is the label | RegisterLabel |
| (Otherwise) | Unclassified |

The label-only rules are deliberately distinct from the prose-following rules: bare tokens like `Vieux` or `Au pluriel` followed by prose are ambiguous (`Vieux marin de…` could begin an ordinary definition), so they are accepted only when the entire indent content is the label. The "main" register and voice-transition patterns require diagnostic adverbs/constructions that are unambiguous regardless of what follows.

Tried in this order; first match wins. Indents matching no pattern are classified as `Unclassified` (method: `Heuristic`).

## Phase 4: Locution and proverb form extraction

**Input/output**: mutates `Indent.canonical_form` and `Indent.canonical_form_source`, and may reclassify some indents.

For indents classified as `Locution`:

1. **Reflexive reclassification**: if plain text matches `^S'[A-Z...]..., v. réfl`, reclassify to `VoiceTransition`. No canonical form extracted.
2. **Exemple extraction**: if the raw content contains `<exemple>...</exemple>`, the inner text becomes the canonical form (`canonical_form_source = :exemple` — the form was printed as such in the source).
3. **Comma splitting**: if the plain text contains a comma, take the text before the first comma (stripped). If this exceeds 60 characters, skip. (`canonical_form_source = :prose` — editorially extracted.)
4. **Fallback**: if none of the above produce a form, the indent keeps `canonical_form=""` and `:none`. This is flagged in the review queue.

For indents classified as `Proverb`, a form printed as `<exemple>` in the source is preferred and keeps `:exemple` provenance, exactly as for locutions. Otherwise form extraction splits at explicit gloss introducers (`c.-à-d.`, `c'est-à-dire`, `se dit`, `pour dire`, `signifie`) and never at bare commas, since proverbs carry internal commas; with no introducer, the whole text is the form. A definition that survives extraction as nothing but the form marks a self-glossing proverb (the definition is retained).

The `canonical_form_source` provenance is carried into TEI emission: `:exemple` forms emit as `<orth>` text content; `:prose` forms emit as `<orth value="…"/>` (reconstructed-form syntax, case preserved as extracted).

## Phase 5: Scope resolution

**Input/output**: mutates `Entry.body` (replacing/reordering `BodyElement`s) and `Sense.indents` (reparenting indents under transitions).

Scope resolution produces three possible outcomes for a transition indent:

- **Inter-sense scope**: a terminal VoiceTransition indent opens a `TransitionGroup` over subsequent senses in the entry body. Handled in pass 1 (5a).
- **Intra-sense scope**: a NatureLabel or VoiceTransition indent absorbs subsequent sibling indents within the same sense as its children. Handled in pass 2 (5b).
- **No scope**: the transition indent remains a leaf node (e.g. terminal with nothing following, or already absorbed by another transition). No restructuring.

Note: inter-sense scoping considers only VoiceTransition, whereas intra-sense scoping considers both NatureLabel and VoiceTransition. This asymmetry is intentional: NatureLabel transitions (e.g. `<nature>Substantivement.</nature>`) partition usage within a sense but do not open new top-level entry structure.

### 5a. Inter-sense scoping

Processes each entry's body sequentially, looking for senses that carry a terminal transition. A terminal transition is an indent that is:

1. The final indent in the sense's indent list.
2. Classified as VoiceTransition.
3. Has no citations attached.

All three conditions must hold. When found:

1. **Scope boundary**: scan forward through subsequent body elements. The scope ends just before the next sense that also has a trailing `VoiceTransition` (with no citations), or at end of body.
2. **Zero-scope**: if there are no subsequent elements, or the scope boundary falls at 0 (the immediately following element is itself a transition carrier), the transition is left in place as an annotation.
3. **Strong vs medium**: the transition's plain text is tested against two patterns: `^S'[A-Z...]..., v. réfl/etc.` → strong, with extracted form and POS; `^[UPPERCASE FORM], v. n|a|réfl|s. m|f|adj` → strong, with extracted form and POS; everything else → medium.
4. **Restructuring**: the transition indent is removed from the source sense. A `TransitionGroup` is created wrapping the scoped body elements. Both the (now shorter) source sense and the new group are emitted to the new body.
5. **Large-scope warning**: if a group scopes more than 15 senses, it is logged as ambiguous.

Inter-sense scoping examines only the last indent of each sense. A VoiceTransition indent that appears at a non-terminal position within a sense is never considered for inter-sense scoping; it is handled exclusively by intra-sense scoping in pass 2.

As of the v0.2.0 build, no transition resolves to strong scope (all 298 classified VoiceTransitions resolve to medium, intra-sense, or zero scope), so the strong-path encodings below are tested but unpopulated. Populating them — deciding which printed transition forms genuinely govern beyond their own sense — is the classification branch's voice-transition scoping work; the 674 `intra_sense_form` review flags are its worklist.

### 5b. Intra-sense scoping

After inter-sense scoping, each sense (including those inside `TransitionGroup`s) has its indents processed: within a sense's indent list, any `NatureLabel` or `VoiceTransition` indent that is not the last in the list absorbs all following non-transition indents as children, up to the next transition or end of list.

## TEI emission

The TEI emitter (`emit_tei.jl`) serializes the enriched, scope-resolved model to TEI Lex-0 XML, conformant with the pinned TEI Lex-0 v0.9.5 RNG (`vendor/tei-lex0-0.9.5/`; validated by `jing` via `scripts/validate_lex0.jl` — see `scripts/README_validation.md`). It is a native string emitter: no DOM in the emit path. Schema-conformance questions are settled empirically by the probe file (`test/probe_lex0.xml`), which isolates one construct per minimal entry and is re-run whenever the vendored schema changes; the RNG's verdicts override the Bowers et al. paper and all project documents where they disagree.

### Entry shell and identity

Every top-level entry carries `xml:id` (see Phase 1i/1j), `xml:lang="fr-x-lit19c"`, and `type="mainEntry"` (`type` is schema-required). Sense `xml:id`s are hierarchical: `{entry_id}_s{body_index}` for top-level senses, `.{child_index}` appended at each nesting level. Nested related entries (locutions/proverbs) extend the parent sense id with a form slug. Id generation is deterministic: identical sources produce byte-identical ids across builds.

### Markup conversion

Gannaz inline markup is converted via the substitution layer plus a stack-based converter that preserves nesting (independent regex passes on nested wrappers produce crossed tags; the tree-aware conversion is required for well-formedness):

| Source | TEI |
|--------|-----|
| `<semantique type="domaine">` | `<usg type="domain">` |
| `<semantique type="indicateur">` / `<semantique>` | routed `<usg>` (see label routing) |
| `<a ref="X">Y</a>` | `<xr type="…"><ref type="entry" target="#id">Y</ref></xr>`, with the target passed through `make_id` normalization |
| `<exemple>` | `<mentioned>` |
| `<nature>` | routed `<gramGrp>`/`<usg>` (see label routing) |
| `<i lang="X">` | `<foreign xml:lang="X">` (any language, not only Latin) |
| `<i>` | `<mentioned>` |

Context flattening: `mentioned` and `foreign` are invalid inside `<etym>`, `<note>`, `<quote>`, and `<def>` per the RNG, and flatten there to `<hi rend="italic">` preserving `xml:lang` — a reversible, information-preserving fallback. Reference wrappers dissolve to bare `<ref>` inside quotes. Interstitial prose inside `<xr>` wraps in `<seg>` (bare text is invalid there).

### Label routing

All usage/grammar label content routes through `src/norms.jl`: normalize (lowercase, strip trailing punctuation), split compound "X et Y" labels into atoms, look up each atom through ordered tiers (exact match → prefix → lemma rules → `^terme` domain tier → residue), and return typed atoms for the caller to place. An atom bound for residue is retried once with any trailing discourse adverbial run stripped (`encore`, `aussi`, `aujourd'hui`, `en ce sens`, `dans le même sens`), the same species as the dropped `et` connector: lookup-only, firing only after every tier has missed, so no previously routed atom can change target. The routed vocabulary is the applicable Lex-0 `usg/@type` set — `socioCultural`, `attitude`, `meaningType`, `temporal`, `frequency`, `textType`, `normativity`, `domain` — plus `<gram>` types (`pos`, `gender`, `number`, `tense`, `valency`, `construction`, `agreement`) emitted inside `<gramGrp>`. Unroutable residue emits as `<usg type="hint">` and is counted per population; residue rates are logged on every build. Tier ordering is load-bearing (exact-before-domain keeps `terme familier` on `socioCultural`; lemma-before-domain keeps `terme vieilli` on `temporal`) and pinned by tests. Conflated POS strings (`s. m.`, `v. réfl.`, `part. passé.`) split into separate typed `<gram>` elements via the POS parser, applied to `entry.pos` and transition POS strings alike.

Inline `<usg>` elements that would land inside `<def>` (invalid per the RNG's `<def>` content model) hoist to sense-level siblings, classified `def_end`/`single_clause`/`uncertain` and recorded in `test/reports/def_usg_hoists.tsv` as the audit trail; uncertain cases hoist anyway, since an over-scoped label is recoverable and a lost one is not. `<pron>` content that is prose commentary rather than a transcription relocates to `<note type="pronunciation">`, with a report file for the discriminator's decisions.

### Label splitting

Three splitting mechanisms handle label/definition separation, each targeting a different content shape.

**`split_label`** (positional, tag-leading), used by Figurative, DomainLabel, and as a final fallback: tries leading `<gramGrp>`, then leading `<usg>`, then leading `Fig.`, then falls back to the entire content as the label with an empty definition.

**`split_gram`** (structural, tag-anchored), used by NatureLabel and VoiceTransition when the source had a `<nature>` tag: splits the converted content into pre-text, label, and definition around the first gram element. Pre-text is classified as `:none`, `:reflexive_form` (starts `Se`/`S'` + verb, label contains `réfl`), `:locution_form` (label matches `loc. adv.` etc.), or `:headword_echo`. When the definition is empty (the tag wrapped both label and definition), the fused string passes to `split_bare_transition` for sub-splitting.

**`split_bare_transition`** (text-pattern, no tag boundary), used for heuristically-classified transition and register indents: matches a known root label, consumes `et …` compound continuations and short interposed adverbial runs (`encore`, `aussi`, `aujourd'hui`, `au singulier`, `au pluriel`, `en ce sens`, `dans le même sens` — Littré routinely interposes these, as in `populairement encore, une ficelle`), and splits at the first `,` `.` `:` separator. Returns `nothing` when no root matches or the separator is missing; the fallback then swallows the whole content as the label. The residual failure class is separator-absent content (`familièrement être encore tout étourdi du bateau`), which surfaces in the routed `hint` residues and belongs to the classification branch's residue audit.

### Role dispatch

Each `IndentRole` has a dedicated `emit_indent` method:

- **Figurative**: `<sense ana="figurative">` with routed `<usg>` label (`@type` on `<sense>` is invalid per the RNG; instance annotation rides `ana`).
- **DomainLabel**: `<sense>` with `<usg type="domain">` label.
- **RegisterLabel**: `<sense>` with routed `<usg>` label(s).
- **Locution / Proverb**: nested `<entry type="relatedEntry">` inside the parent sense, with shell attributes, `<form type="lemma">` (orth per `canonical_form_source` provenance), and a `<sense>` wrapping the definition. Printed `Prov.` markers and proverb-classified items carry `<usg type="meaningType" norm="proverbial">`. Novel `<mentioned>` phrases lift to `<cit type="example">`; content echoing the form or duplicating a sibling citation is discarded; self-glossing proverbs keep the duplicated definition. Migration is driven by adjudicated labels in `test/sampling/locutions_labeled.tsv`; the def-centric metonymic discriminator is flag-only (`metonymic_subsense`).
- **CrossReference**: `<xr type="related">` with inner wrappers dissolved and prose seg-wrapped.
- **NatureLabel / VoiceTransition**: the three-path split described under label splitting, emitting `<gramGrp>` constructs and forms; valency emits at sense level (the Ch. 4 inheritance encoding) pending scope adjudication.
- **Unclassified**: `<sense ana="unclassified">` with any leading `<usg>` elements extracted — the XPath-queryable review surface.

### TransitionGroup dispatch

- **Strong** (`:strong`): nested `<entry type="homonymicEntry">` with `xml:id`/`xml:lang`, `<form type="lemma">` from the transition form, and `<gramGrp>` from the parsed transition POS. (Currently unpopulated; see Phase 5a.)
- **Medium** (`:medium`): `<sense>` with routed label.

### Rubrique dispatch

No rubrique body is wrapped in `<p>` (invalid in the target contexts); content emits as bare text with flattened inline markup.

| Kind | Encoding |
|------|----------|
| Etymologie | `<etym>`, contents constructed (see below) |
| Historique | folded into the entry's (or sense's) single combined `<etym>`, after etymological content: century markers as `<lbl>` (text parseable by `century_range`), attestation citations as `<cit type="example" ana="attestation">`, each with `<date notBefore notAfter>` inside its `<bibl>` |
| Remarque | `<note type="remarque">`, citations as sibling `<cit type="example">` elements |
| Supplement | `<note type="supplément">`, minimal mechanical fixes only |
| Synonyme | `<xr type="synonymy">` with `<lbl>`/`<ref>` children and seg-wrapped prose; citations as flagged siblings |
| Proverbes | `<note type="proverbes">` with sibling citations (content not parsed into individual proverbs) |

### Etymology construction

`src/etym.jl` segments Etymologie content (`segment_etymology`, the single tokenizer shared with the flag pass) into cits, connectors, cross-references, prose, and suspects. Language cues match the longest table key as a suffix, case-insensitively, against `data/etym_language_table.toml`; cue clusters joined by `et`/`ou` split into sibling `<cit type="cognate|etymon">` elements sharing the form, with connectors as `<lbl>`. Each cit carries `xml:lang`, a `<lang expand norm>` preserving the printed abbreviation (omitted when nothing was printed; a full language name governing from prose supplies `xml:lang` with no `<lang>` element), `<form><orth>` (comma-separated variants as `<form type="variant">` siblings), optional `<gloss>` (no attributes — the RNG admits none there), and `<usg type="hint">fictif</usg>` for `lat. fictif` forms. Etymon-vs-cognate rides derivational markers (`du`, `dériv-`, `tiré`, stretch-leading `de`); unmarked cits default to cognate with a `defaulted` model field (logged as a counter, not flagged per-instance). `voy.`/`cf.`/`comparez` tails become `<xr type="related">`. Suspect tokens — adjacent to a form, unmatched by table and stoplist — emit as `<lbl ana="suspect">` and as `suspect_language_token` flags, equal counts by construction. Rubriques whose markup falls outside the segmenter's event inventory emit unsegmented (byte-identical to the flattened fallback) and are counted via `etym_fallback`. Private-use `xml:lang` subtags respect the RFC 3066 eight-character cap (`fr-x-bourg`, not `fr-x-bourguignon`).

### Instance annotation convention

`ana` is the project's channel for instance-level annotation, orthogonal to `type`: `ana="attestation"` (diachronic attestations vs. synchronic examples), `ana="figurative"` (sense-level, replacing the invalid `sense/@type`), `ana="suspect"` (unresolved language-position tokens), `ana="unclassified"` (classifier review surface).

## SQLite emission

### Schema

Six tables: `entries`, `senses`, `citations`, `locutions`, `rubriques`, `review_queue`. See `docs/schema.md` for column-level documentation.

### Sense insertion

Body elements map to `senses` rows:

- `Sense` → `sense_type='sense'`, with `num`, `is_supplement`, and `indent_id` derived as `{entry_id}.{num || 1}`.
- `TransitionGroup` → `sense_type='homonymic_entry'` (strong; renamed from `grammatical_variant` in v0.2.0, mirroring the TEI vocabulary — zero live rows in the current build) or `'usage_group'` (medium), with `transition_type`, `transition_form`, `transition_pos`.
- `Indent` → `sense_type` derived from role (e.g. `'figurative'`, `'locution'`, `'domain'`, `'cross_reference'`, `'register'`, `'unclassified'`, `'annotation'` for childless NatureLabel/VoiceTransition, `'transition_group'` for those with children, `'sense'` as fallback).

All insertions are recursive: each indent's children produce child rows with `parent_sense_id` pointing to the parent's auto-incremented `sense_id`, and `depth` incremented.

### Locutions

An indent classified as `Locution` with a non-empty `canonical_form` produces a row in `locutions` keyed on `sense_id`.

### FTS

Full-text search tables (`senses_fts`, `citations_fts`) are populated after the main transaction commits, using `fts5` content-sync from the base tables.

### Review queue

All `ReviewFlag`s are inserted with `context` serialized as JSON (via JSON.jl).

## Flag collection

Flags are generated post-scope-resolution by `collect_flags` and record items for human review. Aggregate counters (routing residue rates, the etymology resolved-vs-suspect hit rate, `cognate_defaulted`) are logged at collection time rather than flagged per-instance.

### Flag types

Classification and scope: **unclassified** (top-level unclassified indents, with neighboring context; nested unclassified children are enumerable via `senses.sense_type = 'unclassified'`), **skipped_locution**, **likely_locution**, **scope_decision**, **large_scope** (> 15 senses), **large_intra_scope** (> 5 children), **calibration_sample** (stratified, seed=42).

Structural (phase `structural`, added with the TEI conformance work): **metonymic_subsense** (flag-only discriminator on locution glosses), **sense_level_valency** (valency scoped without a printed form), **synonyme_citations**, **intra_sense_form** (printed reflexive/locution forms pending scope adjudication — the classification branch's worklist).

Etymology: **suspect_language_token** (mirrors `ana="suspect"` in the corpus, equal counts by construction), **etym_fallback** (unsegmented etymology rubriques).
