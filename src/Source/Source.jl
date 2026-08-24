"""
The source layer represents what XMLittré contains before Deep-Littré decides what any of it
means. Source identity, byte spans, patches, and the raw/parser-view relation live here;
semantic conclusions do not. Everything a `SourceDocument` exposes is immutable after
construction.
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

export Span, RawSpan, ViewSpan, SourceDocument, Patch

end
