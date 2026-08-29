struct Span{layer}
	file::String
	start_byte::Int
	end_byte::Int
end

const RawSpan = Span{:raw}
const ViewSpan = Span{:view}

layer_name(::Span{layer}) where {layer} = layer

Base.length(span::Span) = span.end_byte - span.start_byte
Base.isempty(span::Span) = span.end_byte == span.start_byte

function Base.show(io::IO, span::Span{layer}) where {layer}
	print(io, layer, "[", span.file, ":", span.start_byte, ":", span.end_byte, ")")
end

function segment(text::AbstractString, start_byte::Int, end_byte::Int)::SubString
	end_byte > start_byte || return SubString(text, start_byte, start_byte - 1)
	SubString(text, start_byte, prevind(text, end_byte))
end

slice(text::AbstractString, span::Span)::SubString = segment(text, span.start_byte, span.end_byte)

is_boundary(text::AbstractString, position::Int)::Bool =
	position == ncodeunits(text) + 1 || (1 <= position <= ncodeunits(text) && isvalid(text, position))

function validate_span(text::AbstractString, span::Span)::Span
	span.start_byte <= span.end_byte ||
		error("inverted span $(span)")
	is_boundary(text, span.start_byte) ||
		error("span start $(span.start_byte) is not a codepoint boundary in $(span.file)")
	is_boundary(text, span.end_byte) ||
		error("span end $(span.end_byte) is not a codepoint boundary in $(span.file)")
	span
end

covers(outer::Span{layer}, inner::Span{layer}) where {layer} =
	outer.file == inner.file &&
	outer.start_byte <= inner.start_byte &&
	inner.end_byte <= outer.end_byte

disjoint(left::Span{layer}, right::Span{layer}) where {layer} =
	left.file != right.file ||
	left.end_byte <= right.start_byte ||
	right.end_byte <= left.start_byte

crosses(left::Span{layer}, right::Span{layer}) where {layer} =
	!disjoint(left, right) && !covers(left, right) && !covers(right, left)

laminar(left::Span{layer}, right::Span{layer}) where {layer} = !crosses(left, right)

text_sha256(text::AbstractString)::String =
	bytes2hex(sha256(Vector{UInt8}(codeunits(text))))

span_sha256(text::AbstractString, span::Span)::String = text_sha256(slice(text, span))

"""
	view_span(file, text, range)

Convert an inclusive XML.jl `sourcespan` range into the project's half-open form. The
end is taken with `nextind` rather than stored as `last(range)`.
"""
function view_span(file::AbstractString, text::AbstractString, range::UnitRange{Int})::ViewSpan
	isempty(range) && return ViewSpan(file, first(range), first(range))
	validate_span(text, ViewSpan(file, first(range), nextind(text, last(range))))
end
