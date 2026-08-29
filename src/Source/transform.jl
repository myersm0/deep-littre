"""
An `Edit` records one contiguous region of raw source replaced by one contiguous region of
the parser view. Both intervals are half-open. A pure insertion has an empty raw interval,
so inserted synthetic markup maps to a zero-width raw boundary rather than pretending to
occupy upstream bytes.
"""
struct Edit
	raw_start::Int
	raw_end::Int
	view_start::Int
	view_end::Int
	line::Int
end

struct TransformMap
	file::String
	edits::Vector{Edit}
end

identity_transform(file::AbstractString) = TransformMap(file, Edit[])

is_identity(transform::TransformMap)::Bool = isempty(transform.edits)

function raw_position(transform::TransformMap, position::Int, side::Symbol)::Tuple{Int, Bool}
	drift = 0
	for edit in transform.edits
		if side === :start
			position < edit.view_start && break
			position == edit.view_start && return (edit.raw_start, false)
			position < edit.view_end && return (edit.raw_start, true)
		else
			position <= edit.view_start && break
			position == edit.view_end && return (edit.raw_end, false)
			position < edit.view_end && return (edit.raw_end, true)
		end
		drift += (edit.view_end - edit.view_start) - (edit.raw_end - edit.raw_start)
	end
	(position - drift, false)
end

"""
	to_raw(transform, span)

Map a parser-view span to the smallest raw interval covering it. The second return value is
true when either boundary fell strictly inside transformed text, meaning the boundary has no
one-to-one raw counterpart and the resulting anchor is a synthetic sub-interval of the
enclosing raw material.
"""
function to_raw(transform::TransformMap, span::ViewSpan)::Tuple{RawSpan, Bool}
	span.file == transform.file ||
		error("span file $(span.file) does not match transform file $(transform.file)")
	(start_byte, start_synthetic) = raw_position(transform, span.start_byte, :start)
	(end_byte, end_synthetic) = raw_position(transform, span.end_byte, :stop)
	(RawSpan(transform.file, start_byte, max(start_byte, end_byte)), start_synthetic || end_synthetic)
end

"""
	to_view(transform, span)

Inverse of `to_raw`: the smallest parser-view interval covering the raw span. Used when an
adjudicated raw anchor must be located in the current parser view.
"""
function view_position(transform::TransformMap, position::Int, side::Symbol)::Int
	drift = 0
	for edit in transform.edits
		if side === :start
			position < edit.raw_start && break
			position == edit.raw_start && return edit.view_start
			position < edit.raw_end && return edit.view_start
		else
			position <= edit.raw_start && break
			position == edit.raw_end && return edit.view_end
			position < edit.raw_end && return edit.view_end
		end
		drift += (edit.view_end - edit.view_start) - (edit.raw_end - edit.raw_start)
	end
	position + drift
end

function to_view(transform::TransformMap, span::RawSpan)::ViewSpan
	span.file == transform.file ||
		error("span file $(span.file) does not match transform file $(transform.file)")
	start_byte = view_position(transform, span.start_byte, :start)
	ViewSpan(transform.file, start_byte, max(start_byte, view_position(transform, span.end_byte, :stop)))
end
