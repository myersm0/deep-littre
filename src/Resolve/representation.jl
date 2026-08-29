abstract type Inline end

struct TextRun <: Inline
	text::String
	span::RawSpan
end

struct CrossReference <: Inline
	text::String
	span::RawSpan
	target::String
	resolved::Union{Nothing, RawSpan}
end

CrossReference(text::String, span::RawSpan, target::String) =
	CrossReference(text, span, target, nothing)

struct Emphasis <: Inline
	text::String
	span::RawSpan
	source_element::String
	language::Union{Nothing, String}
end

Emphasis(text::String, span::RawSpan) = Emphasis(text, span, "i", nothing)

inline_text(item::TextRun) = item.text
inline_text(item::CrossReference) = item.text
inline_text(item::Emphasis) = item.text

plain_text(items::Vector{Inline})::String = join(inline_text(item) for item in items)

"""
A qualification is never merely "on the block": its scope is an explicit target reference.
`ContainedScope` is the deterministic default — the marker governs the innermost node containing
it — and needs no adjudication. `AssertedScope` records a departure established by the
qualification-scope pass, carrying the raw span of the material the marker actually governs.
"""
abstract type ScopeTarget end

struct ContainedScope <: ScopeTarget end

struct AssertedScope <: ScopeTarget
	target::RawSpan
end

scope_name(::ContainedScope) = "containment"
scope_name(::AssertedScope) = "adjudicated"

"""
A qualification recovered deterministically from explicit source markup. `printed` is what
Littré prints; `norm` is the committed normalization. `usg` and `gram` are distinguished because
they occupy different TEI positions.
"""
struct Qualification
	channel::Symbol
	type::String
	norm::String
	printed::String
	span::RawSpan
	scope::ScopeTarget
end

Qualification(channel, type, norm, printed, span) =
	Qualification(channel, type, norm, printed, span, ContainedScope())

rescope(qualification::Qualification, scope::ScopeTarget) = Qualification(
	qualification.channel, qualification.type, qualification.norm, qualification.printed,
	qualification.span, scope,
)

"""
A named constituent of a node, retained with its anchor so downstream readers can recover the
material *between* constituents — most often the punctuation separating a form from its gloss,
which no element boundary can express.
"""
struct NodeConstituent
	name::String
	span::RawSpan
	text::String
end

"""
`author` is what Littré prints. Where that is `ID.`, `resolved_author` carries the antecedent
author when the immediately preceding citation names one. `resolution` distinguishes a recovered
name, a valid antecedent with no author, and a genuinely missing antecedent.
"""
struct Citation
	span::RawSpan
	quotation::Vector{Inline}
	author::String
	resolved_author::String
	resolution::Symbol
	reference::String
end

"""
One node of the resolved semantic representation.

`node_type` is `nothing` where the semantic type remains underdetermined: the container has not
been examined under every structural alternative, so no ordinary `Sense` can be derived. Such a
node is serialized coarsely and truthfully, carrying no claim that an adjudicator established
anything about it.
"""
struct ResolvedNode
	node_id::String
	node_type::Union{Nothing, Adjudication.NodeType}
	span::RawSpan
	number::Union{Nothing, String}
	form::Union{Nothing, String}
	constituents::Vector{NodeConstituent}
	separator::Union{Nothing, String}
	definition::Vector{Inline}
	qualifications::Vector{Qualification}
	citations::Vector{Citation}
	children::Vector{ResolvedNode}
end

struct AnchoredEtymSegment
	segment::Any
	span::RawSpan
end

"""
Rubrique content in source order. `<note>` cannot hold `<cit>` under Lex-0, so a rubrique's
citations must be lifted to entry level while its prose stays in a note; keeping the items in one
ordered sequence is what lets the renderer interleave them faithfully rather than sorting prose
away from the citations it introduces.
"""
abstract type RubriqueItem end

struct RubriqueLabel <: RubriqueItem
	kind::String
	text::String
	not_before::Union{Nothing, Int}
	not_after::Union{Nothing, Int}
	span::RawSpan
end

"""
A citation carries the range of the century header that introduces it. Littré prints the century
once over a group of attestations, so without carrying it the range survives only as prose and
nothing in either output is queryable by date. The carry happens here rather than in each renderer:
both must agree, and neither is permitted to infer.
"""
struct RubriqueCitation <: RubriqueItem
	citation::Citation
	subtype::String
	date_text::String
	not_before::Union{Nothing, Int}
	not_after::Union{Nothing, Int}
end

RubriqueCitation(citation, subtype) = RubriqueCitation(citation, subtype, "", nothing, nothing)

struct RubriqueProse <: RubriqueItem
	content::Vector{Inline}
	span::RawSpan
end

struct ResolvedRubrique
	name::String
	span::RawSpan
	items::Vector{RubriqueItem}
	etymology::Vector{AnchoredEtymSegment}
end

struct ResolvedEntry
	entry_id::String
	headword::String
	homograph::Union{Nothing, Int}
	span::RawSpan
	pronunciation::Union{Nothing, String}
	grammar::Vector{Qualification}
	nodes::Vector{ResolvedNode}
	rubriques::Vector{ResolvedRubrique}
end

struct ReviewFinding
	category::String
	detail::String
	span::RawSpan
end

struct PassCoverage
	pass::String
	pass_version::Int
	population::String
	population_version::Int
	population_size::Int
	population_hash::String
	examined::Int
	positive::Int
	negative::Int
	unresolved::Int
	stale::Int
end

struct ResolvedCorpus
	entries::Vector{ResolvedEntry}
	review::Vector{ReviewFinding}
	coverage::Vector{PassCoverage}
end
