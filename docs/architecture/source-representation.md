# Source representation

Deep-Littré separates upstream bytes from the patched parser view without making either coordinate system adjudication identity.

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
