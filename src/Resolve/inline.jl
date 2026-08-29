"""
Inline content assembly. A node's definition is the ordered residual content of its span after
structural child nodes, promoted qualification markers, citations, and other separately emitted
block-level facts are carved out. Inline semantic and presentational structures are transformed
in place rather than removed, so a cross-reference stays inside the definition.
"""
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

function flush_run!(builder::InlineBuilder)
	text = String(take!(builder.buffer))
	isempty(text) && return nothing
	push!(builder.items, TextRun(
		text, Source.to_raw(builder.document.transform, ViewSpan(
			builder.document.file, builder.start_byte, builder.end_byte,
		))[1],
	))
	builder.start_byte = 0
	builder.end_byte = 0
	nothing
end

"""
Absorb a text node, skipping any sub-intervals carved out by an exclusion. A structural child is
often a sub-range of a text node rather than an element, so exclusion has to cut into text rather
than only skip whole elements.

"""
function absorb_text!(builder::InlineBuilder, span::ViewSpan, excluded::Vector{ViewSpan})
	cuts = sort(
		filter(candidate -> !Source.disjoint(candidate, span), excluded);
		by = candidate -> candidate.start_byte,
	)
	position = span.start_byte
	for cut in cuts
		cut.start_byte > position &&
			absorb_run!(builder, ViewSpan(span.file, position, min(cut.start_byte, span.end_byte)))
		flush_run!(builder)
		position = max(position, cut.end_byte)
		(builder.pending_space === nothing || isempty(builder.pending_space)) &&
			(builder.pending_space = ViewSpan(span.file, position, position))
	end
	position < span.end_byte && absorb_run!(builder, ViewSpan(span.file, position, span.end_byte))
	nothing
end

function remember_space!(builder::InlineBuilder, span::ViewSpan)
	pending = builder.pending_space
	if pending === nothing || isempty(pending)
		builder.pending_space = span
	elseif pending.file == span.file && pending.end_byte == span.start_byte
		builder.pending_space = ViewSpan(span.file, pending.start_byte, span.end_byte)
	else
		builder.pending_space = span
	end
	nothing
end

function emit_pending_space!(builder::InlineBuilder)
	pending = builder.pending_space
	pending === nothing && return nothing
	if builder.buffer.size > 0
		write(builder.buffer, ' ')
	elseif !isempty(builder.items)
		(raw, _) = Source.to_raw(builder.document.transform, pending)
		push!(builder.items, TextRun(" ", raw))
	end
	builder.pending_space = nothing
	nothing
end

"""
	decode_reference(source, position, limit)

The decoded text of the entity or character reference beginning at `position`, and the position
after it, or `nothing` when no reference resolves there. Semantic text is what Littré wrote, not
what XML syntax required, so `&amp;` reaches the renderers and the routing tables as `&`; escaping
on the way out is the serializer's business alone.
"""
function decode_reference(source::AbstractString, position::Int, limit::Int)
	source[position] == '&' || return nothing
	semicolon = findnext(';', source, position)
	(semicolon === nothing || semicolon >= limit) && return nothing
	following = nextind(source, semicolon)
	reference = Source.segment(source, position, following)
	decoded = XML.unescape(reference)
	decoded == reference ? nothing : (decoded, following)
end

function absorb_run!(builder::InlineBuilder, span::ViewSpan)
	source = builder.document.parser_view
	position = span.start_byte
	while position < span.end_byte
		reference = decode_reference(source, position, span.end_byte)
		if reference !== nothing
			(decoded, following) = reference
			absorb_character!(builder, first(decoded), position, following)
			position = following
			continue
		end
		character = source[position]
		following = nextind(source, position)
		absorb_character!(builder, character, position, following)
		position = following
	end
	nothing
end

function absorb_character!(
	builder::InlineBuilder, character::AbstractChar, position::Int, following::Int,
)
	file = builder.document.file
	if isspace(character)
		remember_space!(builder, ViewSpan(file, position, following))
	else
		if builder.start_byte == 0
			emit_pending_space!(builder)
			builder.start_byte = position
		elseif builder.pending_space !== nothing
			emit_pending_space!(builder)
		end
		write(builder.buffer, character)
		builder.end_byte = following
	end
	nothing
end

function push_item!(builder::InlineBuilder, item::Inline)
	flush_run!(builder)
	emit_pending_space!(builder)
	push!(builder.items, item)
	nothing
end

carved(span::ViewSpan, excluded::Vector{ViewSpan})::Bool =
	any(candidate -> Source.covers(candidate, span), excluded)

function gather_inline!(
	builder::InlineBuilder, node::XML.FlatNode, excluded::Vector{ViewSpan},
)
	for child in XML.children(node)
		gather_node!(builder, child, excluded)
	end
	nothing
end

function gather_node!(builder::InlineBuilder, child::XML.FlatNode, excluded::Vector{ViewSpan})
	document = builder.document
	kind = XML.nodetype(child)
	span = Source.node_view_span(document, child)
	if kind == XML.Text
		absorb_text!(builder, span, excluded)
	elseif kind == XML.Element
		name = XML.tag(child)
		if carved(span, excluded) || name == "rubrique"
			flush_run!(builder)
			(builder.pending_space === nothing || isempty(builder.pending_space)) &&
				(builder.pending_space = ViewSpan(span.file, span.end_byte, span.end_byte))
		else
			if name == "a"
				reference = something(Source.attribute(child, "ref"), "")
				push_item!(builder, CrossReference(
					collapse_inline(document, child),
					Source.to_raw(document.transform, span)[1],
					reference,
					builder.references === nothing ? nothing :
						resolve_reference(builder.references, reference),
				))
			elseif name in ("i", "exemple", "mentioned", "foreign")
				language = Source.attribute(child, "lang")
				language === nothing && (language = Source.attribute(child, "xml:lang"))
				push_item!(builder, Emphasis(
					collapse_inline(document, child),
					Source.to_raw(document.transform, span)[1],
					name,
					language,
				))
			else
				gather_inline!(builder, child, excluded)
			end
		end
	end
	nothing
end

"""
	inline_from(document, nodes; excluded = ViewSpan[])

Inline content assembled from an explicit run of sibling nodes rather than from a whole element.
Rubrique prose arrives as the material between citations, which is a slice of a paragraph's
children, not a subtree. Optional exclusions carve deterministic lead labels out of that prose
without losing the remaining inline structure.
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
	trim_inline(builder.items)
end

function collapse_inline(document::Source.SourceDocument, node::XML.FlatNode)::String
	builder = InlineBuilder(document)
	gather_inline!(builder, node, ViewSpan[])
	flush_run!(builder)
	strip(plain_text(builder.items))
end

function inline_content(
	document::Source.SourceDocument, node::XML.FlatNode, excluded::Vector{ViewSpan},
	references = nothing,
)::Vector{Inline}
	builder = InlineBuilder(document, references)
	gather_inline!(builder, node, excluded)
	flush_run!(builder)
	trim_inline(builder.items)
end

function trim_inline(items::Vector{Inline})::Vector{Inline}
	trimmed = Inline[item for item in items if !isempty(inline_text(item))]
	while !isempty(trimmed) && isempty(strip(inline_text(first(trimmed))))
		popfirst!(trimmed)
	end
	while !isempty(trimmed) && isempty(strip(inline_text(last(trimmed))))
		pop!(trimmed)
	end
	trimmed
end
