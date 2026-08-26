"""
Semantic node types. `Sense` is never asserted by an adjudicator; it is derived by the resolver
from structural exhaustion. It appears here because it belongs to the same closed vocabulary.
"""
abstract type NodeType end

struct Sense <: NodeType end
struct SubLemma <: NodeType end
struct VoiceVariant <: NodeType end

node_type_name(::Sense) = "Sense"
node_type_name(::SubLemma) = "SubLemma"
node_type_name(::VoiceVariant) = "VoiceVariant"

node_type(name::AbstractString)::NodeType =
	name == "Sense" ? Sense() :
	name == "SubLemma" ? SubLemma() :
	name == "VoiceVariant" ? VoiceVariant() :
	error("unknown node type $(name)")

form_bearing(::Sense) = false
form_bearing(::SubLemma) = true
form_bearing(::VoiceVariant) = true

const structural_alternatives = (SubLemma(), VoiceVariant())
const structural_alternative_set_version = 1
const closure_protocol_version = 1

const outcomes = (:positive, :negative, :unresolved)

struct Constituent
	name::String
	span::RawSpan
end

struct NodeAssertion
	node_id::String
	node_type::NodeType
	span::RawSpan
	parent::Union{Nothing, String}
	constituents::Vector{Constituent}
end

"""
A scope adjudication: this qualification marker governs that target, rather than the block that
happens to contain it. The target is a raw span, not a node id, because the node it lands on may
be derived at resolution time and have no durable identity.
"""
struct ScopeAssertion
	assertion_id::String
	marker::RawSpan
	target::RawSpan
end

"""
What the adjudicator was shown alongside the target. Provenance only: a reference must lie inside
the record's own raw span, whose hash therefore already covers it.
"""
struct ContextReference
	span::RawSpan
	role::String
end

"""
One eligible source block examined by one pass. `negative` means the pass looked and the class does
not apply; an absent record means it has not looked. `decision_procedure` and `decision_reference`
are opaque: how a verdict was reached is not interpreted here.
"""
struct ExaminationRecord
	record_id::String
	pass::String
	pass_version::Int
	population::String
	population_version::Int
	source::RawSpan
	raw_sha256::String
	synthetic_boundary::Bool
	projection::String
	projection_version::Int
	view_sha256::String
	context::Vector{ContextReference}
	outcome::Symbol
	exhaustive::Bool
	assertions::Vector{NodeAssertion}
	scopes::Vector{ScopeAssertion}
	residuals::Vector{RawSpan}
	decision_procedure::String
	decision_reference::Union{Nothing, String}
	created::String
	notes::String
end

"""
	with(record; field = value...)

A copy of the record with named fields replaced. Tests and re-anchoring both need to alter one
field of a committed record; doing that positionally breaks every time the schema grows a field.
"""
with(record::ExaminationRecord; overrides...) = ExaminationRecord(
	(
		get(NamedTuple(overrides), name, getfield(record, name))
		for name in fieldnames(ExaminationRecord)
	)...,
)

sort_key(record::ExaminationRecord) = (
	record.source.file, record.source.start_byte, record.source.end_byte,
	record.pass, record.record_id,
)
