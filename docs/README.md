# Deep-Littré documentation

These documents explain how to read Deep-Littré's output, how the pipeline works, and the serialization rules it follows.

If you want to use the published TEI or SQLite, start with [`reading-the-output.md`](reading-the-output.md). It follows one entry from XMLittré to the output and explains Littré's conventions along the way, and [`known-limitations.md`](known-limitations.md) and [`tei-lex0-examples.md`](tei-lex0-examples.md) assume it.

If you want to work on the pipeline, start with [`architecture/overview.md`](architecture/overview.md), which introduces the vocabulary the rest of these documents use by following one entry from the source file to the published output. The other architecture documents assume it. For the project as a whole, see the top-level [`README.md`](../README.md); each `src/*/README.md` explains one layer's implementation, while these documents state the contracts those layers implement.

## Using the output

- [`reading-the-output.md`](reading-the-output.md): Littré's conventions, XMLittré's markup, and how both appear in the TEI and SQLite, worked through APOTHICAIRE.
- [`known-limitations.md`](known-limitations.md): what the output doesn't do yet and what that means for your queries, with the pipeline detail behind each limitation.

## Architecture

- [`architecture/overview.md`](architecture/overview.md): blocks, adjudication, projection, nodes, qualifications and closure, worked through ANGOISSE and DISPENSER.
- [`architecture/semantic-model.md`](architecture/semantic-model.md): span-anchored nodes, qualifications, relations, scope targets, coverage populations, and the derivation of ordinary senses by exhaustion.
- [`architecture/source-representation.md`](architecture/source-representation.md): raw and patched source views, spans, transform mapping, patch behaviour, the classifier-facing projection, and release provenance.
- [`architecture/adjudication-authoring.md`](architecture/adjudication-authoring.md): the authoring harness, the classification surface, selections, and record applicability.
- [`architecture/adjudication-rendering.md`](architecture/adjudication-rendering.md): how records are applied, structural closure, coverage, and the normative TEI and SQLite renderer contracts.

## TEI Lex-0

- [`tei-lex0-compliance.md`](tei-lex0-compliance.md): serialization rules against the pinned TEI Lex-0 v0.9.5 RNG.
- [`tei-lex0-examples.md`](tei-lex0-examples.md): worked source-to-TEI examples illustrating those rules; section 16, the decomposition carrier, is provisional for v0.4.

## Classification campaign

These describe how the v0.4 campaign builds and measures adjudications.

- [`campaign/benchmark-regime.md`](campaign/benchmark-regime.md): per-pass ground truth, sample frames and roles, provenance, contamination, and evaluation priorities.
- [`campaign/decomposition-guidance.md`](campaign/decomposition-guidance.md): versioned adjudication guidance for the `decomposition` pass.
- [`campaign/decomposition-notes.md`](campaign/decomposition-notes.md): samples drawn so far, the two-stage design, and open questions.