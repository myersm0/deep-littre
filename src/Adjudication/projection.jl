"""
One interval of projected text and where it came from. Literal segments copy parser-view material
byte for byte. A decoded entity or character reference is mapped rather than literal: the projected
character maps to the complete source reference, so a selection touching it anchors the whole
reference. Synthetic whitespace carries no source interval.
"""
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
	push!(builder.segments, ProjectionSegment(builder.position, builder.position + 1, 0, 0, true, false))
	builder.position += 1
	nothing
end

function append_run!(builder::ProjectionBuilder, text::AbstractString, view_start::Int, view_end::Int)
	projected_width = ncodeunits(text)
	view_width = view_end - view_start
	projected_width == view_width ||
		error("literal projection segment changes byte width at $(builder.file):$(view_start):$(view_end)")
	write(builder.buffer, text)
	previous = isempty(builder.segments) ? nothing : last(builder.segments)
	if previous !== nothing && !previous.synthetic && previous.literal &&
		previous.projected_end == builder.position && previous.view_end == view_start
		builder.segments[end] = ProjectionSegment(
			previous.projected_start, builder.position + projected_width,
			previous.view_start, view_end, false, true,
		)
	else
		push!(builder.segments, ProjectionSegment(
			builder.position, builder.position + projected_width, view_start, view_end, false, true,
		))
	end
	builder.position += projected_width
	nothing
end

function append_mapped!(builder::ProjectionBuilder, text::AbstractString, view_start::Int, view_end::Int)
	isempty(text) && return nothing
	write(builder.buffer, text)
	projected_width = ncodeunits(text)
	push!(builder.segments, ProjectionSegment(
		builder.position, builder.position + projected_width, view_start, view_end, false, false,
	))
	builder.position += projected_width
	nothing
end

function absorb_literal!(builder::ProjectionBuilder, source::AbstractString, span::ViewSpan)
	position = span.start_byte
	run_start = 0
	while position < span.end_byte
		character = source[position]
		following = nextind(source, position)
		if isspace(character)
			run_start == 0 || append_run!(builder, segment(source, run_start, position), run_start, position)
			run_start = 0
			builder.pending_space = builder.position > 1
		else
			if run_start == 0
				builder.pending_space && append_space!(builder)
				builder.pending_space = false
				run_start = position
			end
		end
		position = following
	end
	run_start == 0 || append_run!(builder, segment(source, run_start, span.end_byte), run_start, span.end_byte)
	nothing
end

function absorb_mapped!(builder::ProjectionBuilder, text::AbstractString, view_start::Int, view_end::Int)
	length(text) == 1 ||
		error("$(builder.file): entity reference at view byte $(view_start) did not resolve to one character")
	character = first(text)
	if isspace(character)
		builder.pending_space = builder.position > 1
	else
		builder.pending_space && append_space!(builder)
		builder.pending_space = false
		append_mapped!(builder, text, view_start, view_end)
	end
	nothing
end

function absorb!(builder::ProjectionBuilder, source::AbstractString, span::ViewSpan)
	position = span.start_byte
	literal_start = position
	while position < span.end_byte
		if source[position] == '&'
			semicolon = findnext(';', source, position)
			if semicolon !== nothing && semicolon < span.end_byte
				reference_end = nextind(source, semicolon)
				reference = segment(source, position, reference_end)
				decoded = XML.unescape(reference)
				if decoded != reference
					literal_start < position && absorb_literal!(
						builder, source, ViewSpan(builder.file, literal_start, position),
					)
					absorb_mapped!(builder, decoded, position, reference_end)
					position = reference_end
					literal_start = position
					continue
				end
			end
		end
		position = nextind(source, position)
	end
	literal_start < span.end_byte && absorb_literal!(
		builder, source, ViewSpan(builder.file, literal_start, span.end_byte),
	)
	nothing
end

function gather!(builder::ProjectionBuilder, document::Source.SourceDocument, node::XML.FlatNode)
	for child in XML.children(node)
		kind = XML.nodetype(child)
		if kind == XML.Text
			absorb!(builder, document.parser_view, Source.node_view_span(document, child))
		elseif kind == XML.Element
			skipped_in_projection(XML.tag(child)) || gather!(builder, document, child)
		end
	end
	nothing
end

function project(document::Source.SourceDocument, node::XML.FlatNode)::ProjectedView
	builder = ProjectionBuilder(document.file)
	gather!(builder, document, node)
	ProjectedView(
		block_text_projection,
		block_text_version,
		document.file,
		Source.node_view_span(document, node),
		String(take!(builder.buffer)),
		builder.segments,
	)
end

function to_view(projection::ProjectedView, projected_start::Int, projected_end::Int)::Union{Nothing, ViewSpan}
	covering = filter(projection.segments) do candidate
		!candidate.synthetic &&
			candidate.projected_end > projected_start &&
			candidate.projected_start < projected_end
	end
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
	ViewSpan(projection.file, view_start, view_end)
end

function to_projected(projection::ProjectedView, view::ViewSpan)::Union{Nothing, ProjectedSpan}
	view.file == projection.file ||
		error("span file $(view.file) does not match projection file $(projection.file)")
	covering = filter(projection.segments) do candidate
		!candidate.synthetic &&
			candidate.view_end > view.start_byte &&
			candidate.view_start < view.end_byte
	end
	isempty(covering) && return nothing
	leading = first(covering)
	trailing = last(covering)
	projected_start = if leading.literal
		leading.projected_start + max(0, view.start_byte - leading.view_start)
	else
		leading.projected_start
	end
	projected_end = if trailing.literal
		trailing.projected_end - max(0, trailing.view_end - view.end_byte)
	else
		trailing.projected_end
	end
	projected_end > projected_start || return nothing
	ProjectedSpan(projected_start, projected_end)
end

function projected_text(projection::ProjectedView, view::ViewSpan)::String
	span = to_projected(projection, view)
	span === nothing && return ""
	projected_text(projection, span)
end

struct SelectionFailure <: Exception
	selection::String
	reason::String
end

Base.showerror(io::IO, failure::SelectionFailure) =
	print(io, "selection ", repr(failure.selection), " failed: ", failure.reason)

function locate_projected(projection::ProjectedView, selection::AbstractString)::ProjectedSpan
	isempty(strip(selection)) && throw(SelectionFailure(selection, "empty selection"))
	matches = findall(selection, projection.text)
	isempty(matches) && throw(SelectionFailure(selection, "no match in the projected target"))
	length(matches) == 1 ||
		throw(SelectionFailure(selection, "$(length(matches)) matches; selection is ambiguous"))
	found = only(matches)
	ProjectedSpan(first(found), nextind(projection.text, last(found)))
end

function locate(projection::ProjectedView, selection::AbstractString)::ViewSpan
	span = locate_projected(projection, selection)
	view = to_view(projection, span.start_byte, span.end_byte)
	view === nothing && throw(SelectionFailure(selection, "selection maps to no source-visible material"))
	view
end

projected_text(projection::ProjectedView, span::ProjectedSpan)::String =
	String(segment(projection.text, span.start_byte, span.end_byte))
