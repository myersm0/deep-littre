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

const outcomes = (:positive, :negative, :unresolved)

struct ProjectedSpan
	start_byte::Int
	end_byte::Int
end

Base.length(span::ProjectedSpan) = span.end_byte - span.start_byte

projected_covers(outer::ProjectedSpan, inner::ProjectedSpan)::Bool =
	outer.start_byte <= inner.start_byte && outer.end_byte >= inner.end_byte

projected_disjoint(left::ProjectedSpan, right::ProjectedSpan)::Bool =
	left.end_byte <= right.start_byte || right.end_byte <= left.start_byte

projected_laminar(left::ProjectedSpan, right::ProjectedSpan)::Bool =
	projected_disjoint(left, right) || projected_covers(left, right) || projected_covers(right, left)

struct Constituent
	name::String
	span::ProjectedSpan
end

struct NodeAssertion
	node_id::String
	node_type::NodeType
	span::ProjectedSpan
	constituents::Vector{Constituent}
end

struct ScopeAssertion
	marker::ProjectedSpan
	target::ProjectedSpan
end

struct ExaminationRecord
	record_id::String
	pass::String
	pass_version::Int
	source::RawSpan
	surface_sha256::String
	outcome::Symbol
	assertions::Vector{NodeAssertion}
	scopes::Vector{ScopeAssertion}
	residuals::Vector{ProjectedSpan}
	decision_procedure::String
	decision_reference::Union{Nothing, String}
	created::String
	notes::String
end

struct AnchoredConstituent
	name::String
	span::RawSpan
end

struct AnchoredNodeAssertion
	node_id::String
	node_type::NodeType
	span::RawSpan
	constituents::Vector{AnchoredConstituent}
end

struct AnchoredScopeAssertion
	marker::RawSpan
	target::RawSpan
end

struct AppliedRecord
	record_id::String
	pass::String
	pass_version::Int
	source::RawSpan
	outcome::Symbol
	assertions::Vector{AnchoredNodeAssertion}
	scopes::Vector{AnchoredScopeAssertion}
	residuals::Vector{RawSpan}
end

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
