# Source representation

Deep-Littré separates upstream bytes from the patched parser view without making either coordinate system adjudication identity. The upstream bytes are XMLittré, an intermediate digital edition of Littré rather than a transparent representation of the printed dictionary.

## Relationship to the print edition

XMLittré combines transcription with editorial normalization and interpretation. Its distributed XML therefore contains facts about Gannaz's edition as well as facts inherited from Littré: author abbreviations may be expanded, `<exemple>` marks spans that are not typographically distinguished in print, and rubrique structure records editorially encoded scope and position.

Deep-Littré treats explicit XMLittré markup deterministically because it is explicit in the upstream edition, but does not thereby claim that every such fact is directly printed in Littré. Byte anchors establish traceability to XMLittré, not independent fidelity to the page image. Where XMLittré and the print differ, a raw anchor faithfully identifies the XMLittré reading.

Some divergences cannot be reconstructed from XMLittré alone. In particular, author-expansion policy varies by author and requires comparison with page images to recover the printed abbreviation. These are documented fidelity limits rather than silently corrected by the pipeline.

## XML reader

XML.jl parses `parser_view`. Element source spans are indexed once per document and converted to half-open byte intervals.

## Source views

- `raw_text`: upstream XMLittré bytes after encoding validation;
- `parser_view`: raw text after committed patches;
- `TransformMap`: ordered raw/view edit intervals.

The census and resolved representation retain raw spans so output facts remain traceable to the upstream source. Classification records, however, persist their semantic subspans relative to projected classifier text.

## Patches and transform mapping

A patch's line number identifies the source line on which its exact `old` text begins. `old` and `new` may span lines and may differ in line count or byte length.

Each patch is narrowed to its minimal changed interval and recorded as an `Edit`. Coordinate translation then depends on the edit map rather than on a global line-preservation constraint.

This means a harmless earlier insertion can move a later census block without invalidating a classification verdict: if its canonical classification surface is unchanged, its projected selections materialize against the new coordinates.

## Classification coordinates

The `block_text` projection removes descendant blocks/citations, strips markup, decodes entity/character references, and collapses whitespace while retaining a mapping from projected bytes back to parser-view bytes.

Durable adjudication selections are `ProjectedSpan`s. Runtime application maps them to view spans and then raw spans.

## Release provenance

A release records one `patched_source_sha256` over the complete patched parser-view corpus in deterministic filename order. That checksum supports reproducibility claims and is independent of per-verdict stale detection.
