# Deep-Littré documentation

This directory contains the normative design and serialization documentation for the v0.3 rewrite.

The v0.2 pipeline remains available from its release tag. Its implementation-oriented `pipeline.md` and SQLite `schema.md` describe the historical architecture and should not be copied forward as current design documents.

## Normative documents

### Architecture

- [`architecture/semantic-model.md`](architecture/semantic-model.md) — semantic model: span-anchored nodes, qualifications, relations, scope targets, coverage, and derivation of ordinary senses.
- [`architecture/rewrite-v0.3.md`](architecture/rewrite-v0.3.md) — clean-slate rewrite decision, disposition of the previous migration plan, development sequence, and retirement gates for v0.2.
- [`architecture/source-representation.md`](architecture/source-representation.md) — raw/patched/projected source layers, XML.jl 0.4.x reader decision, source spans, transform mapping, patch behavior, and release-source provenance.
- [`architecture/adjudication-rendering.md`](architecture/adjudication-rendering.md) — adjudication application, coverage, structural closure, and the normative TEI/SQLite renderer contracts.
- [`architecture/adjudication-authoring.md`](architecture/adjudication-authoring.md) — authoring harness, adjudication projection and provenance map, LLM/human/rule interfaces, constituent span resolution, and failure policy.

### TEI Lex-0

- [`tei-lex0-compliance.md`](tei-lex0-compliance.md) — normative serialization rules against the pinned TEI Lex-0 v0.9.5 RNG.
- [`tei-lex0-examples.md`](tei-lex0-examples.md) — representative source-to-TEI examples illustrating those rules and the v0.3 semantic model.

## Authority order

When documents disagree, use this order:

1. the pinned TEI Lex-0 RNG and committed probe verdicts for schema-conformance questions;
2. the v0.3 architectural documents for Deep-Littré's internal semantic and provenance model;
3. the TEI compliance and examples documents for serialization policy;
4. historical v0.2 documentation and implementation behavior as a preservation oracle, not as an architectural constraint.

A schema-valid v0.2 corpus is an important regression oracle, but v0.3 is intentionally allowed to change structure where the new adjudication model makes a more accurate claim.
