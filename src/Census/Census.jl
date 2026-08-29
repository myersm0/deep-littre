"""
Which source blocks exist for adjudication, and the fixed denominator coverage is measured
against. See `src/Census/README.md`.
"""
module Census

using SHA
using XML

using ..Source
using ..Source: RawSpan, ViewSpan

include("blocks.jl")

export SourceBlock, SourceEntry, SourceRubrique, CorpusCensus, DocumentCensus

end
