"""
What XMLittré contains, before anything decides what it means.
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

export Span, RawSpan, ViewSpan, SourceDocument, Patch, anchor_id, source_paths,
	patched_corpus_sha256

end
