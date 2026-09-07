struct ProjectionSegment
	projected_start::Int
	projected_end::Int
	view_start::Int
	view_end::Int
	synthetic::Bool
	literal::Bool
end

struct ProjectedView
	name::String
	version::Int
	file::String
	target::ViewSpan
	text::String
	segments::Vector{ProjectionSegment}
end

const block_text_projection = "block_text"
const block_text_version = 2
const block_text_description = "Direct content of one source block: descendant blocks and \
citations excluded, markup stripped, entity and character references decoded, whitespace runs \
collapsed."

skipped_in_projection(name::AbstractString)::Bool =
	name in ("indent", "variante", "rubrique", "résumé", "cit")

# ===== building a projection =====

mutable struct ProjectionBuilder
	file::String
	buffer::IOBuffer
	segments::Vector{ProjectionSegment}
	position::Int
	pending_space::Bool
end

ProjectionBuilder(file::AbstractString) =
	ProjectionBuilder(file, IOBuffer(), ProjectionSegment[], 1, false)

function append_space!(builder::ProjectionBuilder)
	write(builder.buffer, ' ')
	push!(builder.segments, ProjectionSegment(
		builder.position, builder.position + 1, 0, 0, true, false,
	))
	builder.position += 1
	return nothing
end

continues_run(::Nothing, builder::ProjectionBuilder, view_start::Int)::Bool = false

function continues_run(
	previous::ProjectionSegment, builder::ProjectionBuilder, view_start::Int,
)::Bool
	return !previous.synthetic &&
		previous.literal &&
		previous.projected_end == builder.position &&
		previous.view_end == view_start
end

function append_run!(
	builder::ProjectionBuilder, text::AbstractString, view_start::Int, view_end::Int,
)
	projected_width = ncodeunits(text)
	if projected_width != view_end - view_start
		error(
			"literal projection segment changes byte width at " *
			"$(builder.file):$(view_start):$(view_end)",
		)
	end
	write(builder.buffer, text)
	previous = isempty(builder.segments) ? nothing : last(builder.segments)
	if continues_run(previous, builder, view_start)
		builder.segments[end] = ProjectionSegment(
			previous.projected_start, builder.position + projected_width,
			previous.view_start, view_end, false, true,
		)
	else
		push!(builder.segments, ProjectionSegment(
			builder.position, builder.position + projected_width,
			view_start, view_end, false, true,
		))
	end
	builder.position += projected_width
	return nothing
end

function append_mapped!(
	builder::ProjectionBuilder, text::AbstractString, view_start::Int, view_end::Int,
)
	isempty(text) && return nothing
	write(builder.buffer, text)
	projected_width = ncodeunits(text)
	push!(builder.segments, ProjectionSegment(
		builder.position, builder.position + projected_width,
		view_start, view_end, false, false,
	))
	builder.position += projected_width
	return nothing
end

function absorb_literal!(
	builder::ProjectionBuilder, source::AbstractString, span::ViewSpan,
)
	position = span.start_byte
	run_start = 0
	while position < span.end_byte
		character = source[position]
		following = nextind(source, position)
		if isspace(character)
			if run_start != 0
				text = slice(source, run_start, position)
				append_run!(builder, text, run_start, position)
			end
			run_start = 0
			builder.pending_space = builder.position > 1
		elseif run_start == 0
			builder.pending_space && append_space!(builder)
			builder.pending_space = false
			run_start = position
		end
		position = following
	end
	if run_start != 0
		append_run!(
			builder, slice(source, run_start, span.end_byte), run_start, span.end_byte,
		)
	end
	return nothing
end

function absorb_mapped!(
	builder::ProjectionBuilder, text::AbstractString, view_start::Int, view_end::Int,
)
	if length(text) != 1
		error(
			"$(builder.file): entity reference at view byte $(view_start) " *
			"did not resolve to one character",
		)
	end
	if isspace(first(text))
		builder.pending_space = builder.position > 1
		return nothing
	end
	builder.pending_space && append_space!(builder)
	builder.pending_space = false
	append_mapped!(builder, text, view_start, view_end)
	return nothing
end

function decoded_reference(source::AbstractString, position::Int, end_byte::Int)
	source[position] == '&' || return nothing
	semicolon = findnext(';', source, position)
	isnothing(semicolon) && return nothing
	semicolon < end_byte || return nothing
	reference_end = nextind(source, semicolon)
	reference = slice(source, position, reference_end)
	decoded = XML.unescape(reference)
	decoded == reference && return nothing
	return (decoded, reference_end)
end

function absorb!(builder::ProjectionBuilder, source::AbstractString, span::ViewSpan)
	position = span.start_byte
	literal_start = position
	while position < span.end_byte
		reference = decoded_reference(source, position, span.end_byte)
		if isnothing(reference)
			position = nextind(source, position)
			continue
		end
		(decoded, reference_end) = reference
		if literal_start < position
			absorb_literal!(
				builder, source, ViewSpan(builder.file, literal_start, position),
			)
		end
		absorb_mapped!(builder, decoded, position, reference_end)
		position = reference_end
		literal_start = position
	end
	if literal_start < span.end_byte
		absorb_literal!(
			builder, source, ViewSpan(builder.file, literal_start, span.end_byte),
		)
	end
	return nothing
end

function gather!(
	builder::ProjectionBuilder, document::Source.SourceDocument, node::XML.FlatNode,
)
	for child in XML.children(node)
		nodetype = XML.nodetype(child)
		if nodetype == XML.Text
			span = Source.node_view_span(document, child)
			absorb!(builder, document.parser_view, span)
		elseif nodetype == XML.Element
			skipped_in_projection(XML.tag(child)) || gather!(builder, document, child)
		end
	end
	return nothing
end

function project(document::Source.SourceDocument, node::XML.FlatNode)::ProjectedView
	builder = ProjectionBuilder(document.file)
	gather!(builder, document, node)
	return ProjectedView(
		block_text_projection,
		block_text_version,
		document.file,
		Source.node_view_span(document, node),
		String(take!(builder.buffer)),
		builder.segments,
	)
end

# ===== moving between the projection and the parser view =====

covering_segments(projection::ProjectedView, inside) =
	filter(candidate -> !candidate.synthetic && inside(candidate), projection.segments)

function to_view(
	projection::ProjectedView, projected_start::Int, projected_end::Int,
)::Union{Nothing, ViewSpan}
	covering = covering_segments(projection, candidate ->
		candidate.projected_end > projected_start &&
		candidate.projected_start < projected_end
	)
	isempty(covering) && return nothing
	leading = first(covering)
	trailing = last(covering)
	view_start = if leading.literal
		leading.view_start + max(0, projected_start - leading.projected_start)
	else
		leading.view_start
	end
	view_end = if trailing.literal
		trailing.view_end - max(0, trailing.projected_end - projected_end)
	else
		trailing.view_end
	end
	view_end > view_start || return nothing
	return ViewSpan(projection.file, view_start, view_end)
end

function to_projected(
	projection::ProjectedView, view_span::ViewSpan,
)::Union{Nothing, ProjectedSpan}
	view_span.file == projection.file ||
		error(
			"span file $(view_span.file) does not match projection file " *
			"$(projection.file)",
		)
	covering = covering_segments(projection, candidate ->
		candidate.view_end > view_span.start_byte &&
		candidate.view_start < view_span.end_byte
	)
	isempty(covering) && return nothing
	leading = first(covering)
	trailing = last(covering)
	projected_start = if leading.literal
		leading.projected_start + max(0, view_span.start_byte - leading.view_start)
	else
		leading.projected_start
	end
	projected_end = if trailing.literal
		trailing.projected_end - max(0, trailing.view_end - view_span.end_byte)
	else
		trailing.projected_end
	end
	projected_end > projected_start || return nothing
	return ProjectedSpan(projected_start, projected_end)
end

projected_text(projection::ProjectedView, span::ProjectedSpan)::String =
	String(slice(projection.text, span.start_byte, span.end_byte))

function projected_text(projection::ProjectedView, view_span::ViewSpan)::String
	span = to_projected(projection, view_span)
	isnothing(span) && return ""
	return projected_text(projection, span)
end

# ===== locating a selection =====

struct SelectionFailure <: Exception
	selection::String
	reason::String
end

Base.showerror(io::IO, failure::SelectionFailure) =
	print(io, "selection ", repr(failure.selection), " failed: ", failure.reason)

selection_error(selection::AbstractString, reason::AbstractString) =
	throw(SelectionFailure(selection, reason))

function locate_projected(
	projection::ProjectedView, selection::AbstractString,
)::ProjectedSpan
	isempty(strip(selection)) && selection_error(selection, "empty selection")
	matches = findall(selection, projection.text)
	isempty(matches) && selection_error(selection, "no match in the projected target")
	length(matches) == 1 ||
		selection_error(selection, "$(length(matches)) matches; selection is ambiguous")
	found = only(matches)
	return ProjectedSpan(first(found), nextind(projection.text, last(found)))
end

function locate(projection::ProjectedView, selection::AbstractString)::ViewSpan
	span = locate_projected(projection, selection)
	view_span = to_view(projection, span.start_byte, span.end_byte)
	isnothing(view_span) &&
		selection_error(selection, "selection maps to no source-visible material")
	return view_span
end
