"""
Durable semantic judgments and the harness that produces them. Facts XMLittré states explicitly
are not adjudications and do not live here. See `src/Adjudication/README.md`.
"""
module Adjudication

using Dates
using JSON
using TOML
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

export ProjectedView, ExaminationRecord, NodeAssertion, Decision, FormSelection,
	Harness, Store, PassDefinition, ReviewItem, StoreIntegrityError, initialize_store!

end
