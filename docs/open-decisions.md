# Open decisions before classification

The pipeline provenance/identity design is now intentionally small: a raw block locator, one hash of the complete classifier-facing surface, projection-relative semantic selections, and one corpus-level patched-source checksum for release provenance.

## 1. Leading qualifications inferred from prose

Explicit `<semantique>` and `<nature>` markers are deterministic source facts. A separate future classification problem is unmarked leading prose such as `Adverbialement.` or compound labels such as `Familièrement et par exagération.`

Before running that pass at scale, settle the durable assertion shape. The likely contract is:

- adjudication selects the exact printed marker span and its target;
- committed normalization tables determine axis/norm deterministically;
- the verdict does not duplicate normalized semantic values;
- ambiguous marker boundaries remain classification questions rather than regex architecture.

## 2. Remaining deterministic corpus-quality findings

Before classification begins, inspect the bounded resolver review tail and decide which findings indicate deterministic pipeline defects versus legitimate source irregularity:

- unrecognized century labels;
- unresolved citation authors;
- etymology suspects.

Fix deterministic bugs now; leave genuine source/review cases explicit.

## 3. First production exercise of structural serialization

This is a validation risk rather than an open design decision. The current production adjudication store is empty, so corpus-wide TEI currently contains zero `relatedEntry`/`homonymicEntry` structures produced from real verdicts. Unit/development-corpus tests exercise both paths, but the first production `SubLemma` and `VoiceVariant` tranches will also be their first corpus-scale serialization exercise.

Before scaling either pass, run a small committed tranche end to end and inspect both TEI and SQLite parity/output counts. Treat any renderer issue found there as a pipeline defect to fix before expanding classification.

## Deferred outside the current pipeline/classification milestone

- peak-memory optimization;
- SQLite FTS;
- generic adjudication migration tooling beyond the current automatic coordinate-drift recovery.

A more elaborate migration tool should be written only if a real future corpus change produces a concrete class of stranded verdicts.
