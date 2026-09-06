struct Span{layer}
	file::String
	start_byte::Int
	end_byte::Int
end

const RawSpan = Span{:raw}
const ViewSpan = Span{:view}

Base.length(span::Span) = span.end_byte - span.start_byte
Base.isempty(span::Span) = span.end_byte == span.start_byte

Base.show(io::IO, span::Span{layer}) where {layer} =
	print(io, layer, "[", span.file, ":", span.start_byte, ":", span.end_byte, ")")

function slice(text::AbstractString, start_byte::Int, end_byte::Int)::SubString
	end_byte > start_byte || return SubString(text, start_byte, start_byte - 1)
	return SubString(text, start_byte, prevind(text, end_byte))
end

slice(text::AbstractString, span::Span)::SubString =
	slice(text, span.start_byte, span.end_byte)

is_boundary(text::AbstractString, position::Int)::Bool =
	position == ncodeunits(text) + 1 || isvalid(text, position)

function validate_span(text::AbstractString, span::Span)::Span
	a = span.start_byte
	b = span.end_byte
	a <= b || error("inverted span $(span)")
	is_boundary(text, a) || error("span start is not a codepoint boundary: $(span)")
	is_boundary(text, b) || error("span end is not a codepoint boundary: $(span)")
	return span
end

"""
    view_span(file, text, range)

Convert an inclusive XML.jl `sourcespan` range into the project's half-open form.
"""
function view_span(
	file::AbstractString, text::AbstractString, range::UnitRange{Int},
)::ViewSpan
	isempty(range) && return ViewSpan(file, first(range), first(range))
	return validate_span(text, ViewSpan(file, first(range), nextind(text, last(range))))
end

covers(outer::Span{layer}, inner::Span{layer}) where {layer} =
	outer.file == inner.file &&
	outer.start_byte <= inner.start_byte &&
	inner.end_byte <= outer.end_byte

overlaps(left::Span{layer}, right::Span{layer}) where {layer} =
	left.file == right.file &&
	left.start_byte < right.end_byte &&
	right.start_byte < left.end_byte

disjoint(left::Span{layer}, right::Span{layer}) where {layer} = !overlaps(left, right)

crosses(left::Span{layer}, right::Span{layer}) where {layer} =
	overlaps(left, right) && !covers(left, right) && !covers(right, left)

laminar(left::Span{layer}, right::Span{layer}) where {layer} = !crosses(left, right)

anchor_id(span::Span)::String =
	string(span.file, ':', span.start_byte, ':', span.end_byte)

text_sha256(text::AbstractString)::String =
	bytes2hex(sha256(Vector{UInt8}(codeunits(text))))

span_sha256(text::AbstractString, span::Span)::String = 
	text_sha256(slice(text, span))
