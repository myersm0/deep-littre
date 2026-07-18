# DeepLittre Test Suite

This directory contains the full test suite for the Deep-Littré pipeline. The tests are organized to reflect the different levels of behavior in the system: end-to-end pipeline execution, structural classification and scoping, and TEI emission.

---

## Test Structure

### 1. `test_pipeline.jl` — End-to-end pipeline test

This file exercises the full pipeline on a small fixture (`e.xml`):

- parse → enrich → scope → emit
- verifies TEI output structure
- verifies SQLite emission
- checks representative classification and scoping behavior

This is the **integration test** for the system.

It answers:
> Does the pipeline produce coherent output for a known input?

---

### 2. `test_classification_transitions.jl` — Classification behavior

Tests how indents are classified, especially:

- `VoiceTransition` (e.g. `Substantivement.`)
- `NatureLabel` (e.g. `<nature>Substantivement.</nature>`)
- `RegisterLabel` (e.g. `Familièrement`)

Key distinction:

- **bare text** → heuristic classification
- **`<nature>`-wrapped text** → deterministic `NatureLabel`

These tests document the current asymmetry between tagged and untagged forms.

---

### 3. `test_scope_synthetic.jl` — Synthetic scoping edge cases

Handwritten fixtures designed to isolate specific structural patterns:

- terminal transitions
- non-terminal transitions
- adjacent transitions
- transitions with citations

These tests probe:

- inter-sense scoping (`TransitionGroup`)
- intra-sense grouping (indent children)
- zero-scope behavior

They answer:
> What exactly does the pipeline do in edge cases?

---

### 4. `test_scope_regression.jl` — Real-source regression tests

Fixtures extracted from actual XMLittré entries:

- `DEVANCIER`
- `DROIT / DROITE`
- `F`

These tests ensure that behavior observed in real data remains stable.

They are intentionally conservative:
- only assert stable structural facts
- avoid overfitting to incidental details

---

### 5. `test_tei_bare_text_label_splitting.jl` — Bare-text label emission

Covers indents with no `<nature>` tag where label and definition must be split from plain text:

Examples:
- `Substantivement, homme cruel...`
- `Familièrement, se dit...`

Verifies:
- `<usg>` contains only the label phrase
- `<def>` contains the definition
- no long “mashed” `<usg>` elements remain

This tests the fix described in:
`bare_text_transition_splitting.md`

---

### 6. `test_tei_nature_indent_emission.jl` — `<nature>`-tagged indent emission

Covers indents where `<nature>` is present but not leading:

Examples:
- `S'ACCOUTUMER, <nature>v. réfl.</nature> ...`
- `En l'air, <nature>loc. adv.</nature> ...`
- `AIGRIR, <nature>v. n.</nature> ...`

Verifies:

- correct split into:
  - `<form><orth>` (when appropriate)
  - `<usg type="gram">`
  - `<def>`
- correct handling of:
  - reflexive forms
  - locution forms
  - headword echoes
  - label-only cases

This tests the `GramSplit`-based emission logic.

---

### 7. `test_tei_variante_register_labels.jl` — Variante-level labels (currently incomplete)

Covers bare-text register labels at the `<variante>` level:

Examples:
- `Familièrement et par exagération. ...`
- `Populairement. ...`

These currently appear inside `<def>` and are **not yet split** into `<usg>` + `<def>`.

Tests in this file are marked with `@test_broken` until the feature is implemented.

---

## Fixtures

Fixtures are located in:

