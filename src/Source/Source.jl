"""
What XMLittré contains, before anything decides what it means. See `src/Source/README.md`.
"""
module Source

using SHA
using TOML
using XML

include("spans.jl")
include("encoding.jl")
include("transform.jl")
include("patches.jl")
include("document.jl")

export Span, RawSpan, ViewSpan, SourceDocument, Patch, source_paths, patched_corpus_sha256

end
