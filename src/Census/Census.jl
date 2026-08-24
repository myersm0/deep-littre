"""
The `SourceBlock` census is derived from the patched parser view and is independent of
semantic traversal. It is universal over the defined adjudication-relevant block population
rather than over every XMLittré element, and answers only which source blocks exist for
adjudication. Each pass later declares a versioned eligible population drawn from it.
"""
module Census

using SHA
using XML

using ..Source
using ..Source: RawSpan, ViewSpan

include("blocks.jl")

export SourceBlock, SourceEntry, SourceRubrique, CorpusCensus, DocumentCensus

end
