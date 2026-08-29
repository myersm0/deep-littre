# Deep-Littré documentation

Design and serialization specifications for the pipeline. These describe how the code behaves, not how it came to.

For an overview, start with the top-level [`README.md`](../README.md). Each `src/*/README.md` explains one layer's implementation; these documents state the contracts those layers implement.

## Architecture

- [`architecture/semantic-model.md`](architecture/semantic-model.md) — span-anchored nodes, qualifications, relations, scope targets, coverage populations, and the derivation of ordinary senses by exhaustion.
- [`architecture/source-representation.md`](architecture/source-representation.md) — raw and patched source views, spans, transform mapping, patch behaviour, the classifier-facing projection, and release provenance.
- [`architecture/adjudication-authoring.md`](architecture/adjudication-authoring.md) — the authoring harness, the classification surface, selections, and record applicability.
- [`architecture/adjudication-rendering.md`](architecture/adjudication-rendering.md) — how records are applied, structural closure, coverage, and the normative TEI and SQLite renderer contracts.

## TEI Lex-0

- [`tei-lex0-compliance.md`](tei-lex0-compliance.md) — serialization rules against the pinned TEI Lex-0 v0.9.5 RNG.
- [`tei-lex0-examples.md`](tei-lex0-examples.md) — worked source-to-TEI examples illustrating those rules.

## Authority order

When documents disagree:

1. the pinned TEI Lex-0 RNG and the committed probe verdicts, for any question of schema conformance;
2. the architecture documents, for Deep-Littré's semantic and provenance model;
3. the TEI compliance and examples documents, for serialization policy.

Where a document and the code disagree, the code is the defect report: one of the two is wrong and the discrepancy is worth resolving rather than tolerating.
