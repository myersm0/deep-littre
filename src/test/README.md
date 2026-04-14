# Tests

This directory contains both synthetic fixtures and real-source regression fixtures for validating the behavior of the Deep-Littré pipeline.

## Fixture types

### Synthetic fixtures (`fixtures/synthetic/`)
Handwritten minimal examples designed to isolate specific structural patterns:
- terminal transitions (e.g. `Substantivement.`)
- wrapped grammatical labels (e.g. `<nature>Au plur.</nature>`)
- adjacent transitions
- edge cases for scope boundaries

These are used to probe and document behavior in isolation.

### Regression fixtures (`fixtures/real/`)
Extracted from real XMLittré entries (e.g. `DEVANCIER`, `DROIT`, `F`).

These tests ensure that changes to the pipeline do not silently alter behavior on representative real data.

## Test philosophy

Tests in this directory document **current pipeline behavior**, not necessarily intended or final behavior.

In particular:
- Classification differences between bare text (e.g. `Substantivement.`) and wrapped markup (e.g. `<nature>Substantivement.</nature>`) are intentional and currently preserved.
- Scope behavior (intra-sense vs inter-sense) is tested as observed, even where it may later be revised.

When modifying pipeline logic:
- If a test fails and the new behavior is *intended*, update the test.
- If a test fails unexpectedly, treat it as a regression.

## Scope-related behaviors covered
The current tests capture three distinct behaviors:
1. No scope (labels remain local)
2. Intra-sense scope (an indent absorbs following indents)
3. Inter-sense scope (a transition creates a `TransitionGroup`)

These distinctions are central to the pipeline design and should be preserved
or deliberately revised.
