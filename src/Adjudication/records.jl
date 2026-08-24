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
const methods = (:human, :llm, :rule)

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

struct ContextReference
	span::RawSpan
	raw_sha256::String
	projection::String
	projection_version::Int
	view_sha256::String
	role::String
end

"""
One eligible source block or target span examined by one pass. `negative` means the pass looked
and the class does not apply; an absent record means the pass has not looked.
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
	llm_input_sha256::Union{Nothing, String}
	outcome::Symbol
	exhaustive::Bool
	assertions::Vector{NodeAssertion}
	residuals::Vector{RawSpan}
	method::Symbol
	adjudicator::String
	model::Union{Nothing, String}
	created::String
	notes::String
end

"""
A deterministic rule establishing one outcome over a whole versioned population. Recorded once
rather than as a record per target, so exhaustion stays economical without committing millions of
hash-dominated lines. `input_hash` covers the ordered per-target raw and view checks the rule
operated on, so the assertion cannot outlive a change to the material it ranged over.
"""
struct BulkAssertion
	bulk_id::String
	pass::String
	pass_version::Int
	rule::String
	rule_version::Int
	population::String
	population_version::Int
	population_hash::String
	input_hash::String
	outcome::Symbol
	method::Symbol
	adjudicator::String
	created::String
end

sort_key(record::ExaminationRecord) = (
	record.source.file, record.source.start_byte, record.source.end_byte,
	record.pass, record.record_id,
)
