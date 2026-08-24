"""
Adjudication holds durable semantic judgments and the harness that produces them. Facts XMLittré
states explicitly are not adjudications and do not live here; they are reconstructed every build
by the resolver from source, code, and the committed normalization tables.
"""
module Adjudication

using Dates
using JSON
using SHA
using UUIDs
using XML

using ..Source
using ..Source: RawSpan, ViewSpan, slice, segment
using ..Census

include("projection.jl")
include("records.jl")
include("canonical.jl")
include("store.jl")
include("harness.jl")

export ProjectedView, ExaminationRecord, NodeAssertion, Decision, SubLemmaSelection,
	Harness, Store, PassDefinition, ReviewItem

end
