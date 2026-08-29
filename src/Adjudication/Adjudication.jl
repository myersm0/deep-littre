"""
Durable semantic judgments and the harness that produces them. Facts XMLittré states explicitly
are not adjudications and do not live here. See `src/Adjudication/README.md`.
"""
module Adjudication

using Dates
using JSON
using UUIDs
using XML

using ..Source
using ..Source: RawSpan, ViewSpan, slice, segment
using ..Census

include("records.jl")
include("projection.jl")
include("canonical.jl")
include("store.jl")
include("harness.jl")

export ProjectedView, ProjectedSpan, ExaminationRecord, NodeAssertion, AppliedRecord,
	AnchoredNodeAssertion, Decision, FormSelection, Harness, Store, PassDefinition, ReviewItem,
	StoreIntegrityError

end
