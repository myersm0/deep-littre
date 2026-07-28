# Deep-Littré

[![CI](https://github.com/myersm0/deep-littre/actions/workflows/ci.yml/badge.svg)](https://github.com/myersm0/deep-littre/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/myersm0/deep-littre)](https://github.com/myersm0/deep-littre/releases/latest)

A deeply structured, computationally enriched edition of Émile Littré's _Dictionnaire de la langue française_ (1872–1877), built on François Gannaz's XMLittré digitization. Available as TEI Lex-0 XML and SQLite.

Littré's dictionary contains 78,599 entries with etymological, historical, and literary citations, covering the language from Old French through the late 19th century. François Gannaz digitized it as custom XML; this project transforms that XML into [TEI Lex-0](https://dariah-eric.github.io/lexicalresources/pages/TEILex0/TEILex0.html), along with an SQLite database for computational use.

The pipeline is not a mechanical format conversion. Gannaz's XML uses a flat `<indent>` element as an overloaded catch-all for sub-senses, figurative uses, domain labels, locutions, register shifts, cross-references, proverbs, and grammatical transitions. The pipeline classifies each indent by semantic role under a strict certain-or-Unclassified regime, extracts canonical forms from locutions and proverbs, resolves scope ambiguities in grammatical transitions, and emits structured TEI that preserves Littré's semantic hierarchy.

> **Status**: As of v0.2.0 the TEI output is schema-valid against TEI Lex-0 v0.9.5: all 78,599 entries validate against the pinned RNG, as does the document as a whole. Classification coverage is still being refined. See [Known limitations](#known-limitations).

## TEI Lex-0 conformance

The emitted XML validates against the TEI Lex-0 v0.9.5 RelaxNG schema (BCDH/tei-lex-0, 2026-02-08), both as a whole document and entry by entry. Validation uses `jing` (libxml2's RelaxNG engine emits false positives on this schema) through `scripts/validate_lex0.jl`, which reports per-entry validity and ranked error signatures; see `scripts/README_validation.md`. The per-entry pass substitutes a synthetic header for the real one, so it cannot see the `<teiHeader>`; document-level errors are therefore reported separately and fail the run on their own, independently of the per-entry gate. Where refinement is incomplete, the encoding uses documented conformant fallbacks (`<usg type="hint">` for unroutable labels, flattened `<hi rend="italic">` for phrase wrappers in restricted contexts). Schema-conformance questions are settled empirically by a probe file (`test/probe_lex0.xml`) of minimal single-construct entries paired with controls, re-validated in CI whenever the pinned schema changes.

## Downloads

Pre-built data products are attached to each [GitHub release](../../releases):

| File | Description | Size (compressed) |
|------|-------------|-------------------|
| `littre.tei.xml.gz` | TEI Lex-0 XML, all 78,599 entries | ~33 MB |
| `littre.db.gz` | SQLite database for computational queries | ~55 MB |

Decompress with `gunzip littre.tei.xml.gz` or equivalent.

## Enrichments over the source

**Structural classification** — 86,957 flat `<indent>` blocks classified into semantic roles: figurative senses, domain labels (`Terme de marine`, `Terme de musique`), register labels (`familièrement`, `populairement`, `par extension`), locutions, proverbs, cross-references, nature labels (`s. m.`, `adj.`), and voice transitions (`v. réfl.`). Indents that no rule matches with certainty are marked `Unclassified` for downstream review rather than being given a best-guess label. 100% coverage; ~33% of indents currently land in a real role, the remainder in `Unclassified` for now.

**Author resolution** — 41,434 "ID." (idem) citations resolved to the actual author by backward scan through the citation chain.

**Locution and proverb extraction** — Canonical forms extracted from locution and proverb definitions, with provenance tracked: forms printed as such in the source emit as `<orth>` text, editorially extracted forms as `<orth value="…"/>`. Locutions and proverbs emit as nested `<entry type="relatedEntry">` per the Lex-0 pattern.

**Scope resolution** — Grammatical transitions (`Se donner, v. réfl.`, `Substantivement`, `Impersonnellement`) scoped to the correct set of following senses and restructured as nested entries or sense groups.

**Usage label routing** — Inline `<semantique>` and `<nature>` markup separated from definitions and routed through calibrated lookup tables (`data/*.toml`) to the Lex-0 `usg/@type` vocabulary (`socioCultural`, `attitude`, `meaningType`, `temporal`, `frequency`, `textType`, `normativity`, `domain`) and to typed `<gram>` elements (`pos`, `gender`, `valency`, `construction`, …) inside `<gramGrp>`. Compound labels split into multiple typed elements; unroutable residue (under 2% per population) emits as `<usg type="hint">` with counts logged on every build.

**Etymology construction** — Etymology sections segmented into `<cit type="etymon">`/`<cit type="cognate">` structure with BCP 47 language tags from a calibrated 149-key abbreviation table (96.7% sampled recognition), printed abbreviations preserved with expansions, historical attestations folded in with machine-readable century dates, and unresolved tokens marked `<lbl ana="suspect">` in the corpus itself (1,423 in the current build, equal to the review-queue count by construction).

**Rubrique preservation** — All rubrique types (étymologie, historique, remarque, supplément, synonyme, proverbes) emitted with complete content, citations, and structured sub-blocks.

**Supplement integration** — 1,178 supplement entries and supplement variantes marked with `source="supplement"` and integrated into the main entry structure.

**Classification overrides** — Support for LLM-assisted reclassification via external verdicts CSV, keyed on source file and line number for traceability.

## TEI structure

Each entry follows this pattern, abridged from actual pipeline output for readability:

```xml
<entry xml:id="envie" xml:lang="fr-x-lit19c" type="mainEntry">
  <form type="lemma">
    <orth norm="envie">ENVIE</orth>
    <pron>an-vie</pron>
  </form>
  <gramGrp>
    <gram type="pos">s.</gram>
    <gram type="gender">f.</gram>
  </gramGrp>
  <sense n="1" xml:id="envie_s1">
    <def>Sentiment de tristesse, d'irritation...</def>
    <cit type="example">
      <quote>L'envie suit la vertu comme l'ombre suit le corps</quote>
      <bibl><author>BOILEAU</author></bibl>
    </cit>
    <sense ana="figurative" xml:id="envie_s1.1">
      <usg type="meaningType" norm="figurative">fig.</usg>
      <def>Le serpent de l'envie</def>
    </sense>
  </sense>
  <!-- ... numbered senses; locutions as nested relatedEntry ... -->
  <etym>
    Provenç. <cit type="cognate"><lang expand="provençal" norm="pro">Provenç.</lang>
    <form><orth>enveia</orth></form></cit> ;
    du lat. <cit type="etymon"><lang expand="latin" norm="la">lat.</lang>
    <form><orth>invidia</orth></form></cit> …
    <lbl>XIIe s.</lbl>
    <cit type="example" ana="attestation">
      <quote>…</quote>
      <bibl><date notBefore="1101" notAfter="1200"/>…</bibl>
    </cit>
  </etym>
</entry>
```

Key conventions:

- Every entry carries `xml:id`, `xml:lang="fr-x-lit19c"`, and `type="mainEntry"`; nested entries (`relatedEntry`, `homonymicEntry`) carry the same shell.
- `<usg>` types use the Lex-0 controlled vocabulary; grammatical labels split into typed `<gram>` elements inside `<gramGrp>`.
- `ana` is the instance-annotation channel: `ana="attestation"` (diachronic attestations, vs. synchronic examples), `ana="figurative"`, `ana="suspect"` (unresolved etymology tokens), `ana="unclassified"` (classifier review surface, queryable by XPath).
- Historical attestations live inside `<etym>` (account first, attestations second), with century markers as `<lbl>` and machine-readable dates in each attestation's `<bibl>`.
- Author abbreviations preserved as-is in display; resolved forms in `<author>` elements.
- Printed forms keep print casing as element text, with normalized forms in attributes (`norm`, `value`); the pipeline never destroys case information.

## SQLite schema

Full schema documentation is available [here](docs/schema.md).

The SQLite database provides a flat, queryable view of the dictionary:

- **entries**: headword, POS, pronunciation, entry_id, source file, supplement flag
- **senses**: definition text, sense number, parent entry, indent role classification (with `sense_type = 'unclassified'` for indents no rule matched), `indent_id` (ASCII-normalized path like `defaut.3.1`), `xml_id` (matching the TEI `xml:id` attribute)
- **citations**: quote text, author (original + resolved), reference, parent sense
- **locutions**: canonical forms keyed to sense_id
- **review_queue**: pipeline-flagged items for human review (unclassified indents, scope decisions, suspect etymology tokens, etc.)

Note for v0.1.0 users: the `sense_type` value `grammatical_variant` was renamed `homonymic_entry` in v0.2.0, mirroring the TEI encoding (zero live rows in the current build, so the break is prospective).

Example queries:

```sql
-- All citations from Molière
SELECT e.headword, c.text_plain, c.reference
FROM citations c
JOIN senses s ON c.sense_id = s.sense_id
JOIN entries e ON s.entry_id = e.entry_id
WHERE c.resolved_author = 'MOLIÈRE';

-- Entries with figurative senses
SELECT DISTINCT e.headword
FROM senses s JOIN entries e ON s.entry_id = e.entry_id
WHERE s.sense_type = 'figurative';

-- All unclassified indents (working surface for review)
SELECT e.headword, s.content_plain
FROM senses s JOIN entries e ON s.entry_id = e.entry_id
WHERE s.sense_type = 'unclassified';

-- Look up a locution
SELECT l.canonical_form, s.content_plain
FROM locutions l
JOIN senses s ON l.sense_id = s.sense_id
WHERE l.canonical_form LIKE '%panneau%';
```

## Building from source

### Requirements

- Julia 1.10+
- Dependencies are managed via `Project.toml` (XML.jl is pinned to 0.3.x; 0.4.x is a breaking rewrite); run `julia --project=. -e 'using Pkg; Pkg.instantiate()'` to install
- Java (for `jing`, bundled in `vendor/`) if running schema validation

### Running the pipeline

Place the Gannaz XML source files (`a.xml` through `z.xml`, `a_prep.xml`) in `data/source/`, then:

```
julia bin/run_pipeline.jl data/source data/output
```

Output: `data/output/littre.tei.xml` and `data/output/littre.db`.

Optional flags:

```
julia bin/run_pipeline.jl data/source data/output \
  --patches patches/patches.toml \
  --verdicts data/verdicts.csv
```

### Validation

```
julia scripts/validate_lex0.jl data/output/littre.tei.xml
```

Validates the document as a whole, then each entry in isolation, reporting per-entry results and ranked error signatures. Any document-level error fails the run on its own, since the release criterion is whole-document validity and the per-entry pass cannot see the header. `--gate N` additionally caps invalid entries at a no-regression floor, and `--baseline` writes the committed report, which records the totals, the ranked signatures, any document-level errors, and the id of every invalid entry. Per-signature counts, not the whole-document error total, are the trustworthy progress metric while errors remain (a resynchronizing validator reveals later errors as earlier ones clear).

### Tests

`julia --project=. -e 'using Pkg; Pkg.test()'` runs the suite, which is hermetic: it needs no source data and no build, since the routing tables and the adjudication table it reads are committed. Schema validation is separate and needs `jing`: `julia --project=. scripts/validate_probe.jl` checks the probe's verdicts against `test/probe_expected.tsv`, and `scripts/validate_lex0.jl` needs a built corpus. Both run in CI.

## Repository structure

```
deep-littre/
├── Project.toml
├── .github/workflows/          CI (tests, probe) and release
├── src/
│   ├── DeepLittre.jl           Module root, using/include/export
│   ├── model.jl                Type definitions (traits, structs, enums)
│   ├── parse.jl                Phase 1: Gannaz XML → internal model
│   ├── enrich.jl               Phases 2–4: author resolution, indent
│   │                           classification, form extraction
│   ├── scope.jl                Phase 5: transition scope resolution
│   ├── flags.jl                Review flag generation
│   ├── norms.jl                Shared label routing (typed atoms from
│   │                           the committed tables in data/)
│   ├── etym.jl                 Etymology segmentation and language table
│   ├── emit_tei.jl             Model → TEI Lex-0 XML
│   └── emit_sqlite.jl          Model → SQLite
├── bin/
│   ├── run_pipeline.jl         CLI entry point
│   └── release.jl              Build, gate, package, checksum
├── scripts/
│   ├── validate_lex0.jl        Schema validation harness (release gate)
│   ├── validate_probe.jl       Probe verdict gate (CI)
│   └── README_validation.md
├── data/
│   ├── usg_register_norms.toml Calibrated label → usg/@type routing
│   ├── usg_gram_norms.toml     Calibrated grammatical label routing
│   ├── etym_language_table.toml Littré abbreviation → BCP 47 (+ expand)
│   ├── source/                 Gannaz XML files (not tracked)
│   └── output/                 Pipeline outputs (not tracked; see Releases)
├── vendor/
│   ├── tei-lex0-0.9.5/         Pinned schema + PROVENANCE.md
│   └── jing.jar
├── test/
│   ├── runtests.jl             Suite driver
│   ├── helpers.jl              Shared TEI parsing accessors
│   ├── probe_lex0.xml          One-construct-per-entry schema probe
│   ├── probe_expected.tsv      Committed probe verdicts
│   ├── lex0_baseline.tsv       Committed validation baseline
│   ├── sampling/               Calibration artifacts (labeled samples,
│   │                           inventories); locutions_labeled.tsv is a
│   │                           live pipeline input, not a test fixture
│   └── fixtures/               Golden entries + synthetic test data
├── patches/
│   └── patches.toml            Source XML corrections (line-targeted)
├── docs/
│   ├── pipeline.md             Phase-by-phase pipeline behavior
│   └── schema.md               SQLite schema guide
├── README.md
└── LICENSE
```

## Design notes

### Type system

Indent roles and rubrique kinds are modeled as trait hierarchies (`abstract type IndentRole end` with concrete singletons like `Figurative`, `DomainLabel`, `Unclassified`, etc.). This enables Julia's multiple dispatch for the emitters — each role gets its own `emit_indent` method rather than a monolithic match/case.

The `Sense`/`TransitionGroup` split (both subtypes of `BodyElement`) cleanly separates regular senses from grammatical transition containers, avoiding the "one struct with dead fields" antipattern.

### Two emitters, one model

The TEI and SQLite emitters are independent interpreters of the shared model, and review flags are generated by a separate model-only pass. Any transform that must route uncertainty to review, or that changes the SQLite vocabulary, therefore lives in the model layer where all three consumers see it; pure serialization concerns live in the emitters. Shared lookup tables live in committed data files readable by both layers. Where a detection feeds both a review flag and an emission decision (the etymology suspect channel), one function performs it for both consumers, so shipped-corpus counts and review-queue counts agree by construction rather than by discipline. See `docs/pipeline.md` for the full statement.

### Strict certain-or-Unclassified classification

Phase 3 follows a strict certainty regime. Classification rules either match enough structural signal to be definitively right, or the indent is left `Unclassified` for downstream review. There is no confidence axis. The `Unclassified` role is a first-class member of the `IndentRole` hierarchy, dispatched on like any other; the alternative — using `nothing` for unmatched indents — would have scattered null checks through downstream code and lost the dispatch uniformity.

This regime trades exhaustive role coverage for high precision. The `Unclassified` bucket is the working surface for follow-up — clustered LLM analysis, new tightened rules, or manual review — rather than a fictional classification baked into the output.

The same philosophy extends to emission: unroutable labels emit as `<usg type="hint">` (the spec's documented interim encoding) rather than guessed types, unresolved etymology tokens are marked `ana="suspect"` rather than silently mapped or deleted, and every such residue is counted and reported per build.

### Schema as arbiter

Conformance claims are settled by validating against the pinned RNG, not by reading documents — including this project's own. The probe file (`test/probe_lex0.xml`) isolates one construct per minimal entry; surprising validator behavior gets a new probe entry before hand-debugging. The published schema diverges from the TEI Lex-0 paper on several load-bearing points (closed `cit/@type` vocabulary, no `<dictScrap>`, no `@type` on `<sense>`, RFC 3066 language-tag datatypes), and the schema wins.

### Immutability with targeted mutation

Most types are immutable structs. `Indent` and `Citation` are mutable because enrichment phases modify their `classification`, `canonical_form`, and `resolved_author` fields in place. `Entry.id` is a `Ref{String}` to allow deduplication without reconstructing entire entries.

### Patches

Source corrections are line-targeted string replacements in TOML format, applied in memory during parse. The constraint is that patches never add or remove lines, so source line numbers are invariant — enabling `SourceLocation` (file + line) on every indent as both a debugging aid and a stable key for classification overrides.

### Classification overrides (verdicts)

LLM-assisted reclassification results are loaded from a CSV keyed on `(file, line)`. They take precedence over heuristic classification but are applied during the same pass. An optional `check` column verifies that the content at the specified line matches expectations.

## Known limitations

- **Unclassified bucket**: 58,599 of 86,957 indents (67.4%) currently fall into `Unclassified`. This is by design — under the strict regime, indents are left unclassified rather than given a best-guess label. The set is queryable via `senses.sense_type = 'unclassified'` (SQLite) or `ana="unclassified"` (TEI) and is the declared frontier for v0.3: reducing it via new tightened rules and LLM-assisted review through the verdicts machinery.
- **Voice-transition scoping**: no transition currently resolves to strong scope, so nested `<entry type="homonymicEntry">` is encoded and tested but unpopulated; 674 printed transition forms sit at sense level pending scope adjudication (`intra_sense_form` review flags).
- **Etymology refinement residues**: 1,423 suspect tokens (`ana="suspect"`, the table-extension worklist), 149 unsegmented etymology rubriques (`etym_fallback`), and phrase wrappers in restricted contexts flattened to `<hi rend="italic">` rather than lifted to richer structure.
- **Résumé blocks**: 96 long entries have tables of contents (`<résumé>` in source) currently emitted as placeholders.
- **Large-scope transitions**: 3 entries have grammatical transitions scoping over >15 senses.
- **Source data errors**: Gannaz's XML contains a small number of errors including missing homograph indices, incorrect `terme` attributes, and accent-collision headwords (31 pairs). These are corrected via `patches/patches.toml`.

## Entry and sense IDs

Entry IDs are ASCII-normalized from the headword: accents stripped, special characters replaced with underscores (`DÉGOÛTÉ, ÉE` → `degoute_ee`). Homograph entries in the source XML carry an index via `sens=` attribute (`degrossi_ie.1`, `degrossi.2`).

When multiple entries produce the same normalized ID — either from accent collisions (`DÉGOUT`/`DÉGOÛT` → both `degout`) or missing homograph indices — all occurrences receive a numeric suffix: `degout_1`, `degout_2`.

## Source patches

Corrections to Gannaz's source XML live in `patches/patches.toml` as line-targeted string replacements. Patches are applied in memory during parse, keeping the originals in `data/source/` untouched. The constraint is that patches never add or remove lines, preserving source line numbers as stable identifiers.

Current categories:

- **cit_tail_splits** (15 patches): Transition labels (`Absolument.`, `Substantivement.`) appear as bare text between citations inside a single `<indent>`. Patch splits the indent at the transition boundary on the same line.
- **missing_homograph_index** (26 patches): Entries that appear multiple times without `sens=` attributes to distinguish them (e.g. ACIDE adj./s. m., CLAUDE s. m./s. f., DI- préfixe). Also includes duplicate `sens=` values (CAME, CULOT, PÉKIN).
- **wrong_terme** (6 patches): Entries where the `terme` attribute doesn't match the actual headword. Includes suffix entries mislabeled with the preceding headword (ESQUAQUE→-ESQUE, GÉNIE→-GÉNIE, INDUVIE→-INE, OYEN→-OYER) and a probable copy error (second ALTAVELLE→ALTE). These errors originate in the upstream `littre.txt`, not in Gannaz's XML conversion.

Additional source errors are expected to surface as the full corpus is processed. Patches can be added incrementally; the pipeline rebuilds deterministically from patched sources.

## Source data

This project builds on:

> François Gannaz, *XMLittré — Le dictionnaire de la langue française d'Émile Littré en XML*, version 1.3.
> [bitbucket.org/Mytskine/xmlittre-data](https://bitbucket.org/Mytskine/xmlittre-data)
> License: [CC-BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)

The underlying text is the *Dictionnaire de la langue française* by Émile Littré, published by Hachette in four volumes (1872–1877) with a supplement (1877). The original text is in the public domain.

## Citing Deep-Littré

A paper describing Deep-Littré is in preparation. In the meantime, if you use Deep-Littré in published research, please cite:

```bibtex
@software{myers-deep-littre,
  author       = {Myers, Michael J.},
  title        = {Deep-Littré: Structural Recovery from a Flat Encoding},
  year         = {2026},
  url          = {https://github.com/myersm0/deep-littre},
  version      = {0.2.0}
}
```

## License

CC-BY-SA 4.0. See [LICENSE](LICENSE).
