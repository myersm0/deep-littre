# Source

`Source` simply reads XMLittré. It preserves upstream text, applies committed repairs, parses the patched view, and maintains coordinate mappings needed by the census and resolver.

## Views and coordinates

`raw_text` is upstream XMLittré as distributed. `parser_view` is the text after committed patches. `RawSpan` and `ViewSpan` are half-open byte intervals.

`TransformMap` records each patched raw interval and its replacement interval. `to_raw` and `to_view` translate spans across the two views. Inserted markup can therefore create synthetic boundaries without pretending those bytes existed upstream.

Raw coordinates are runtime source references. Adjudication identity is the classification surface, not a coordinate.

## Patches

A patch names a file, a source line on which its `old` text begins, the exact old text, and its replacement. The line is only a convenient locator into the immutable upstream file.

`old` and `new` may span multiple lines and may change line count. Patches are still fail-closed:

- `old` may not be empty
- it must begin exactly once on the specified line
- patches must address the file being read
- raw edit intervals may not overlap
- the resulting source must satisfy the encoding and XML parser requirements

The transform map, not line preservation, carries coordinate drift.

## Files

`document.jl` holds `SourceDocument` and the corpus reader. `encoding.jl` validates upstream bytes. `spans.jl` converts XML.jl `sourcespan` ranges to the project's half-open form. `transform.jl` holds `Edit` and `TransformMap`. `patches.jl` reads and applies the committed patch table.

`SourceDocument` builds an element index at construction, mapping every element's parser-view interval to its node. Locating an element by span otherwise means searching from the document root, which at the top level scans every entry in the file — O(blocks × entries) across a build, and comfortably quadratic on a real letter file.

`source_paths` excludes dotfiles. An editor swap file or a macOS AppleDouble sidecar can be named `._a.xml`, which would otherwise enter the census as another document and change the population hash.

## Corpus checksum

`patched_corpus_sha256` computes one SHA-256 over the patched parser-view corpus in filename order. This is release provenance that states which patched source bytes produced an artifact.
