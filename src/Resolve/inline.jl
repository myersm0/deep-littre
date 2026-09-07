# ordered inline content assembly

mutable struct InlineBuilder
	document::Source.SourceDocument
	references::Union{Nothing, CrossReferenceIndex}
	items::Vector{Inline}
	buffer::IOBuffer
	start_byte::Int
	end_byte::Int
	pending_space::Union{Nothing, ViewSpan}
end

InlineBuilder(document::Source.SourceDocument, references = nothing) =
	InlineBuilder(document, references, Inline[], IOBuffer(), 0, 0, nothing)

to_raw(document::Source.SourceDocument, span::ViewSpan)::RawSpan =
	first(Source.to_raw(document.transform, span))

to_raw(builder::InlineBuilder, span::ViewSpan)::RawSpan = to_raw(builder.document, span)

function flush_run!(builder::InlineBuilder)
	text = String(take!(builder.buffer))
	isempty(text) && return nothing
	span = ViewSpan(builder.document.file, builder.start_byte, builder.end_byte)
	push!(builder.items, TextRun(text, to_raw(builder, span)))
	builder.start_byte = 0
	builder.end_byte = 0
	return nothing
end

function push_item!(builder::InlineBuilder, item::Inline)
	flush_run!(builder)
	emit_pending_space!(builder)
	push!(builder.items, item)
	return nothing
end


# ===== whitespace between runs =====

has_pending_space(builder::InlineBuilder)::Bool =
	!isnothing(builder.pending_space) && !isempty(builder.pending_space)

function mark_gap!(builder::InlineBuilder, span::ViewSpan)
	has_pending_space(builder) && return nothing
	builder.pending_space = span
	return nothing
end

function remember_space!(builder::InlineBuilder, span::ViewSpan)
	pending = builder.pending_space
	adjacent = has_pending_space(builder) &&
		pending.file == span.file &&
		pending.end_byte == span.start_byte
	if adjacent
		builder.pending_space = ViewSpan(span.file, pending.start_byte, span.end_byte)
	else
		builder.pending_space = span
	end
	return nothing
end

function emit_pending_space!(builder::InlineBuilder)
	isnothing(builder.pending_space) && return nothing
	if builder.buffer.size > 0
		write(builder.buffer, ' ')
	elseif !isempty(builder.items)
		push!(builder.items, TextRun(" ", to_raw(builder, builder.pending_space)))
	end
	builder.pending_space = nothing
	return nothing
end


# ===== absorbing source text =====

"""
The decoded text of the entity or character reference beginning at `position`, and the
position after it, or `nothing` when no reference resolves there. Semantic text is what
Littré wrote, not what XML syntax required, so `&amp;` reaches the renderers and the
routing tables as `&`; escaping on the way out is the serializer's business alone.
"""
function decode_reference(source::AbstractString, position::Int, limit::Int)
	source[position] == '&' || return nothing
	semicolon = findnext(';', source, position)
	isnothing(semicolon) && return nothing
	semicolon < limit || return nothing
	following = nextind(source, semicolon)
	reference = Source.slice(source, position, following)
	decoded = XML.unescape(reference)
	decoded == reference && return nothing
	return (decoded, following)
end

function absorb_character!(
	builder::InlineBuilder, character::AbstractChar, position::Int, following::Int,
)
	file = builder.document.file
	if isspace(character)
		remember_space!(builder, ViewSpan(file, position, following))
		return nothing
	end
	if builder.start_byte == 0
		emit_pending_space!(builder)
		builder.start_byte = position
	elseif !isnothing(builder.pending_space)
		emit_pending_space!(builder)
	end
	write(builder.buffer, character)
	builder.end_byte = following
	return nothing
end

function absorb_run!(builder::InlineBuilder, span::ViewSpan)
	source = builder.document.parser_view
	position = span.start_byte
	while position < span.end_byte
		reference = decode_reference(source, position, span.end_byte)
		if isnothing(reference)
			following = nextind(source, position)
			absorb_character!(builder, source[position], position, following)
		else
			(decoded, following) = reference
			absorb_character!(builder, first(decoded), position, following)
		end
		position = following
	end
	return nothing
end

"""
Absorb a text node, skipping any sub-intervals carved out by an exclusion. A structural
child is often a sub-range of a text node rather than an element, so exclusion has to
cut into text rather than only skip whole elements.
"""
function absorb_text!(
	builder::InlineBuilder, span::ViewSpan, excluded::Vector{ViewSpan},
)
	cuts = sort(
		filter(candidate -> Source.overlaps(candidate, span), excluded);
		by = candidate -> candidate.start_byte,
	)
	position = span.start_byte
	for cut in cuts
		if cut.start_byte > position
			end_byte = min(cut.start_byte, span.end_byte)
			absorb_run!(builder, ViewSpan(span.file, position, end_byte))
		end
		flush_run!(builder)
		position = max(position, cut.end_byte)
		mark_gap!(builder, ViewSpan(span.file, position, position))
	end
	if position < span.end_byte
		absorb_run!(builder, ViewSpan(span.file, position, span.end_byte))
	end
	return nothing
end


# ===== walking elements =====

abstract type InlineElement end

struct AnchorElement <: InlineElement end
struct OtherElement <: InlineElement end

struct EmphasisElement <: InlineElement
	name::String
end

const inline_elements = Dict{String, InlineElement}(
	"a" => AnchorElement(),
	"i" => EmphasisElement("i"),
	"exemple" => EmphasisElement("exemple"),
	"mentioned" => EmphasisElement("mentioned"),
	"foreign" => EmphasisElement("foreign"),
)

inline_element(name::AbstractString)::InlineElement =
	get(inline_elements, name, OtherElement())

carved(span::ViewSpan, excluded::Vector{ViewSpan})::Bool =
	any(candidate -> Source.covers(candidate, span), excluded)

function gather_element!(::AnchorElement, builder, child, span, excluded)
	reference = something(Source.attribute(child, "ref"), "")
	resolved = isnothing(builder.references) ? nothing :
		resolve_reference(builder.references, reference)
	text = collapse_inline(builder.document, child)
	push_item!(
		builder, CrossReference(text, to_raw(builder, span), reference, resolved),
	)
	return nothing
end

function gather_element!(element::EmphasisElement, builder, child, span, excluded)
	if any(candidate -> Source.overlaps(candidate, span), excluded)
		return gather_inline!(builder, child, excluded)
	end
	language = something(
		Source.attribute(child, "lang"),
		Source.attribute(child, "xml:lang"),
		Some(nothing),
	)
	text = collapse_inline(builder.document, child)
	push_item!(builder, Emphasis(text, to_raw(builder, span), element.name, language))
	return nothing
end

gather_element!(::OtherElement, builder, child, span, excluded) =
	gather_inline!(builder, child, excluded)

function gather_node!(
	builder::InlineBuilder, child::XML.FlatNode, excluded::Vector{ViewSpan},
)
	nodetype = XML.nodetype(child)
	span = Source.node_view_span(builder.document, child)
	nodetype == XML.Text && return absorb_text!(builder, span, excluded)
	nodetype == XML.Element || return nothing
	name = XML.tag(child)
	if carved(span, excluded) || name == "rubrique"
		flush_run!(builder)
		return mark_gap!(builder, ViewSpan(span.file, span.end_byte, span.end_byte))
	end
	return gather_element!(inline_element(name), builder, child, span, excluded)
end

function gather_inline!(
	builder::InlineBuilder, node::XML.FlatNode, excluded::Vector{ViewSpan},
)
	for child in XML.children(node)
		gather_node!(builder, child, excluded)
	end
	return nothing
end


# ===== assembled content =====

"""
Inline content assembled from an explicit run of sibling nodes rather than from a whole
element. Rubrique prose arrives as the material between citations, which is a slice of a
paragraph's children, not a subtree. Optional exclusions carve deterministic lead labels
out of that prose without losing the remaining inline structure.
"""
function inline_from(
	document::Source.SourceDocument, nodes::Vector{XML.FlatNode}, references = nothing;
	excluded::Vector{ViewSpan} = ViewSpan[],
)::Vector{Inline}
	builder = InlineBuilder(document, references)
	for node in nodes
		gather_node!(builder, node, excluded)
	end
	flush_run!(builder)
	return trim_inline(builder.items)
end

function inline_content(
	document::Source.SourceDocument, node::XML.FlatNode, excluded::Vector{ViewSpan},
	references = nothing,
)::Vector{Inline}
	builder = InlineBuilder(document, references)
	gather_inline!(builder, node, excluded)
	flush_run!(builder)
	return trim_inline(builder.items)
end

function collapse_inline(document::Source.SourceDocument, node::XML.FlatNode)::String
	builder = InlineBuilder(document)
	gather_inline!(builder, node, ViewSpan[])
	flush_run!(builder)
	return strip(plain_text(builder.items))
end

has_text(item::Inline)::Bool = !isempty(inline_text(item))

has_visible_text(item::Inline)::Bool = !isempty(strip(inline_text(item)))

function trim_inline(items::Vector{Inline})::Vector{Inline}
	trimmed = Inline[item for item in items if has_text(item)]
	first_visible = findfirst(has_visible_text, trimmed)
	isnothing(first_visible) && return Inline[]
	return trimmed[first_visible:findlast(has_visible_text, trimmed)]
end
