"""
A projection is the exact textual surface on which a judgment is made. It is named and
versioned, and it carries a provenance map from projected intervals back to parser-view
intervals, so an adjudicator can select material without ever handling source coordinates.

Non-synthetic segments are byte-identical copies of parser-view material, which is what makes
offset arithmetic inside a segment exact.
"""
struct ProjectionSegment
	projected_start::Int
	projected_end::Int
	view_start::Int
	view_end::Int
	synthetic::Bool
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
const block_text_version = 1

view_sha256(projection::ProjectedView)::String = bytes2hex(sha256(codeunits(projection.text)))

"""
Elements skipped by the `block_text` projection: descendant source blocks, which are their own
adjudication targets, and citations, which the renderer emits as separate block-level facts.
Everything else contributes its source-visible text with tags stripped.
"""
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
	push!(builder.segments, ProjectionSegment(builder.position, builder.position + 1, 0, 0, true))
	builder.position += 1
	nothing
end

function append_run!(builder::ProjectionBuilder, text::AbstractString, view_start::Int, view_end::Int)
	write(builder.buffer, text)
	width = view_end - view_start
	previous = isempty(builder.segments) ? nothing : last(builder.segments)
	if previous !== nothing && !previous.synthetic &&
			previous.projected_end == builder.position && previous.view_end == view_start
		builder.segments[end] = ProjectionSegment(
			previous.projected_start, builder.position + width, previous.view_start, view_end, false,
		)
	else
		push!(builder.segments, ProjectionSegment(
			builder.position, builder.position + width, view_start, view_end, false,
		))
	end
	builder.position += width
	nothing
end

function absorb!(builder::ProjectionBuilder, source::AbstractString, span::ViewSpan)
	occursin('&', slice(source, span)) &&
		error("$(builder.file): entity reference at view byte $(span.start_byte); \
			the block_text projection requires literal source text")
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

"""
	project(document, node)

Build the `block_text` projection of one source block. The result is the block's direct content:
descendant source blocks and citations are excluded, markup is stripped, and whitespace runs are
collapsed to a single space.
"""
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

"""
	to_view(projection, projected_start, projected_end)

Translate a half-open projected interval to the smallest parser-view interval covering its
source-visible characters. Purely synthetic layout at either boundary is trimmed away. Returns
`nothing` when the selection contains no source-visible material.
"""
function to_view(projection::ProjectedView, projected_start::Int, projected_end::Int)::Union{Nothing, ViewSpan}
	covering = filter(projection.segments) do candidate
		!candidate.synthetic &&
			candidate.projected_end > projected_start &&
			candidate.projected_start < projected_end
	end
	isempty(covering) && return nothing
	leading = first(covering)
	trailing = last(covering)
	view_start = leading.view_start + max(0, projected_start - leading.projected_start)
	view_end = trailing.view_end - max(0, trailing.projected_end - projected_end)
	view_end > view_start || return nothing
	ViewSpan(projection.file, view_start, view_end)
end

struct SelectionFailure <: Exception
	selection::String
	reason::String
end

Base.showerror(io::IO, failure::SelectionFailure) =
	print(io, "selection ", repr(failure.selection), " failed: ", failure.reason)

"""
	locate(projection, selection)

Resolve an adjudicator's projected substring to a parser-view span. The match must be unique
under the pass matching policy; zero or ambiguous matches fail closed rather than guessing.
"""
function locate(projection::ProjectedView, selection::AbstractString)::ViewSpan
	isempty(strip(selection)) && throw(SelectionFailure(selection, "empty selection"))
	matches = findall(selection, projection.text)
	isempty(matches) && throw(SelectionFailure(selection, "no match in the projected target"))
	length(matches) == 1 ||
		throw(SelectionFailure(selection, "$(length(matches)) matches; selection is ambiguous"))
	found = only(matches)
	span = to_view(projection, first(found), nextind(projection.text, last(found)))
	span === nothing && throw(SelectionFailure(selection, "selection maps to no source-visible material"))
	span
end
