"""
The only place that decides what the corpus means: explicit source markup plus durable judgments,
resolved into the representation both renderers consume. See `src/Resolve/README.md`.
"""
module Resolve

using TOML
using Unicode
using UUIDs
using XML

using ..Source
using ..Source: RawSpan, ViewSpan
using ..Census
using ..Adjudication

include("norms.jl")
include("etymology.jl")
include("representation.jl")
include("references.jl")
include("inline.jl")
include("derive.jl")

export ResolvedCorpus, ResolvedEntry, ResolvedNode, Qualification, Citation, resolve

end
