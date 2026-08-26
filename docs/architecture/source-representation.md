# Source representation and anchoring

Status: **normative source-layer specification for v0.3**.

## Purpose

The source layer represents what XMLittré contains before Deep-Littré decides what that content means.

Source identity, source hierarchy, byte spans, patches, normalization, and the `SourceBlock` census belong here. `SubLemma`, `VoiceVariant`, usage qualifications, ordinary senses, and other semantic conclusions do not.

The source representation is immutable after construction.

## XML reader decision

v0.3 uses **XML.jl, pinned to exactly 0.4.6** (`XML = "=0.4.6"`). `FlatNode` remains
experimental and XML.jl warns that its API may change within 0.4.x, so the constraint is an
exact pin rather than a `0.4` range.

The decisive API is provided by the source-retaining readers `LazyNode` and `FlatNode`:

- `sourcetext(node)` returns a zero-copy view of the node's original source text;
- `sourcespan(node)` returns the range of valid Julia string indices occupied by that node;
- `Cursor(data, startpos)` permits a cursor to begin at a known source offset;
- the readers share `XML.XMLTokenizer`, whose tokens are represented by source ranges.

This removes the v0.2 line-queue/scanner coupling. A parsed source node and its position are properties of the same parser object rather than two traversals that must remain synchronized.

`FlatNode` is the required production reader because the pipeline visits essentially the entire tree and repeatedly needs complete element spans. Its stored span data makes this access appropriate for corpus-wide traversal. `FlatNode` is experimental in XML.jl 0.4.x, so the source layer should depend only on accessor semantics also available on `LazyNode`, but the readers are **not** treated as performance-interchangeable. `LazyNode` re-tokenizes on demand and is retained as a correctness/reference fallback for development and differential tests, not as the corpus-scale execution plan.

In week one, benchmark full-corpus parse, traversal, and span extraction with the exact pinned `FlatNode` version. A `FlatNode` correctness defect is an early blocker to work around while the architecture is still cheap to change; it is not deferred until adjudication data exists.

The old XML.jl 0.3 behavior is not preserved. In 0.4, whitespace text nodes between elements are retained; code that wants elements uses `elements`/`eachelement` rather than positional assumptions such as `doc[end]`.

## Three source views

The pipeline distinguishes three representations:

1. **raw source** — immutable upstream XMLittré bytes as distributed;
2. **patched source** — raw source after committed editorial source corrections;
3. **parser view** — patched source after any normalization still required by the v0.3 reader/renderer.

The parser is handed the parser view. XML.jl `sourcespan` therefore identifies a span in that view, not directly in raw source.

The durable adjudication anchor remains the raw source.

**All three v0.2 text normalizations are retired**, so in v0.3 the parser view is the patched
source, byte for byte:

- `xml:space="preserve"` injection is unnecessary because XML.jl 0.4.x retains inter-element whitespace;
- `nom="PROVERBE"`/`nom="REMARQUES"` rewriting becomes attribute canonicalization performed by
  the reader, leaving source bytes untouched;
- `<span lang="la">` rewriting becomes element equivalence recognized at read time, which also
  retires the cross-line `s` flag and preserves the line-local invariant.

The position map is therefore exercised only by patches. The three-view vocabulary is retained
because a future normalization would reintroduce the distinction, and the layer is written
against the general contract rather than against the current identity.

## Canonical span

A canonical source span is a half-open interval of raw UTF-8 byte positions:

```text
(file, start_byte, end_byte)  representing [start_byte, end_byte)
```

`start_byte` points to the first byte of the span. `end_byte` points immediately after its final character.

Julia string indices are byte offsets constrained to codepoint boundaries. XML.jl reports source ranges using valid string indices. When converting an XML.jl inclusive range to the canonical half-open form, the end is computed with `nextind(source, last(range))`, not by storing `last(range)` directly.

Parser-derived element boundaries therefore satisfy the UTF-8 boundary requirement by construction. Editorial sub-spans computed inside element text must still validate both endpoints explicitly.

## Mapping parser-view spans to raw source

Every source transformation produces a deterministic position map in addition to transformed text.

The map has two jobs:

- translate parser-view span boundaries back to raw byte boundaries;
- identify transformed bytes that have no one-to-one raw counterpart.

The implementation may use a line-scoped edit map because all allowed transforms preserve line count, but the API is expressed generally as a position map rather than as a promise that replacement lengths are equal.

For unchanged text, mapping is identity. For replacement text, the map retains the raw interval replaced. For inserted synthetic markup, the inserted bytes map to a zero-width raw boundary.

A parser-view element created by a split patch therefore does not pretend that its inserted `<indent>` tags existed upstream. Its durable raw anchor is the corresponding sub-interval of the enclosing raw indent, and it carries `synthetic_boundary = true` plus patch provenance.

## Source transform invariants

The following are build failures:

- a patch replacement contains a newline;
- a patch's `old` text occurs zero times or more than once on its target line;
- patching changes line count;
- patching changes bytes on a line not named by a patch;
- normalization changes line count;
- an input file violates the repository's declared encoding/BOM/newline policy;
- a transformed node span cannot be mapped back to a valid raw interval.

The initial corpus policy should assert UTF-8, no BOM, and LF line endings if the full-corpus census confirms the sample's observed form. XML.jl readers perform BOM stripping/transcoding in some input paths; Deep-Littré must reject such input rather than allow invisible coordinate rewriting beneath stored anchors.

Normalization rules are intentionally few. Each must have a documented semantic or parser purpose and a regression test. v0.2 normalizations are not grandfathered.

## Raw and adjudicated-view checks

Every durable adjudication carries two independent checks.

### Raw anchor check

The record stores the raw span plus a hash of the raw bytes in that interval. Application fails if the bytes no longer match.

This proves the record still names the same upstream material.

### Adjudicated-view check

The record also stores:

- a projection identifier and version;
- a hash of the exact projected text shown to the adjudicator.

This catches the case where a later patch or projection change alters what Deep-Littré presents while the upstream raw bytes remain unchanged.

The projection is versioned independently of the patch set. An unrelated patch elsewhere in the file must not invalidate a judgment.

The adjudication surface uses an explicit, versioned projection defined by the authoring harness. A projection produces both the displayed text and a provenance map from displayed intervals back to parser-view/raw source intervals. The first production projection is named and versioned before any adjudication records are committed; `strip_tags` is not silently assumed merely because v0.2 used it for verdict checks. See `adjudication-authoring.md`.

Projection provenance is not restricted to one-to-one byte copies. Literal text maps byte-for-byte; decoded XML entity and character references map the projected character to the complete source reference (for example projected `&` to source `&amp;`); collapsed layout whitespace may be synthetic. A selection touching a decoded reference therefore anchors the whole reference rather than inventing byte-level correspondence inside it.

## Source objects

The source layer exposes at least:

```text
SourceDocument
    file
    raw_hash
    parser_view_hash
    transform_map
    entries

SourceEntry
    source_id
    raw_span
    source attributes
    ordered children

SourceBlock
    source_id
    kind
    raw_span
    parser_view_span
    synthetic_boundary
    ordered children
```

`source_id` is a repository-internal convenience identifier, not adjudication identity and not a published TEI `xml:id`. The raw span and checks are the durability contract.

A `SourceBlock` kind is source syntax, not semantic classification. `SourceBlock` kinds are:

- `indent`;
- `variante`;
- `resume_indent` — an `<indent>` with a `<résumé>` ancestor;
- `resume_variante` — a `<variante option="résumé">` inside `<résumé>`;
- `rubrique_indent` — an `<indent>` with a `<rubrique>` ancestor;
- `rubrique_variante` — a `<variante>` with a `<rubrique>` ancestor;
- `entete_nature` — `<nature>` inside `<entete>`.

Résumé and rubrique material are distinct kinds rather than attributes on `indent`/`variante` so
that accidental inclusion in a pass population is harder. Containment is decided by ancestry, not
by element name, and résumé ancestry is consulted for `<indent>` and `<variante>` alike.

`resume_indent` exists because the full corpus contains three `<indent>` elements directly inside
`<résumé>`, in FAIRE, LAISSER, and PRENDRE. PRENDRE's carries a `<semantique>` marker and is
otherwise indistinguishable from ordinary sense material; only its ancestry identifies it as a
summary of senses represented elsewhere in the entry. The 25-entry development corpus contains no
such case, so this was invisible until the full-corpus census.

`prononciation` is source data but is not a `SourceBlock` in this census. It remains represented by the source layer and handled by its own form/commentary path.

`<nature>` appearing inline inside an eligible `<indent>` or `<variante>` is **not** a
`SourceBlock`. It is markup within that block and may become one or more grammatical
qualification markers.

Kinds are modeled as singleton types rather than an enumeration, so that an unhandled kind
raises at the dispatch site instead of falling through a catch-all branch.

Rubriques themselves are source objects with addressable spans because qualifications and relations may target a rubrique.

## SourceBlock census

The `SourceBlock` census is derived from the **patched parser view**, because patches can create blocks that the pipeline and adjudicators actually see.

Every census item retains its durable raw anchor through the transform map.

The census is independent of semantic traversal. It must therefore include `SourceBlock`s even when no adjudication pass currently supports them.

The census is **universal over the defined `SourceBlock` population**, not over every byte or XML element in XMLittré. It answers “which adjudication-relevant source blocks exist?” rather than “what source material of every kind exists?”. Versioned pass populations are selected from this fixed denominator. A pass may legitimately exclude a block kind, but it may not make that `SourceBlock` disappear from the corpus count.

The full-corpus `SourceBlock` census runs before adjudication work begins and is reproducible from source plus committed patches/normalization rules.

## Parser verification

Before the first committed span-anchored adjudications, CI verifies at least:

- `sourcetext(node)` equals the slice named by `sourcespan(node)` for representative and adversarial nodes;
- an element's span covers its complete serialized source extent, including its closing tag;
- source ranges refer to the exact string passed to `parse`;
- `<résumé>` and other non-ASCII element names round-trip without coordinate or text changes;
- `FlatNode` and `LazyNode` produce equivalent source objects on the development corpus;
- the exact pinned `FlatNode` version completes full-corpus parse, traversal, and span extraction within an acceptable operational envelope;
- full-corpus inputs satisfy the encoding/BOM/newline policy.

These tests are assertions about the pinned XML.jl version. If the dependency changes, they run before any new release is accepted.
