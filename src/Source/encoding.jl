struct EncodingViolation <: Exception
	file::String
	reason::String
end

Base.showerror(io::IO, violation::EncodingViolation) =
	print(io, "encoding policy violation in ", violation.file, ": ", violation.reason)

const utf8_byte_order_mark = UInt8[0xef, 0xbb, 0xbf]

"""
	check_encoding(bytes, file)

The declared corpus policy is UTF-8, no byte order mark, LF line endings. XML.jl performs
transcoding and mark stripping on some input paths, which would rewrite coordinates beneath
stored anchors, so violating input is rejected rather than accepted.
"""
function check_encoding(bytes::Vector{UInt8}, file::AbstractString)
	length(bytes) >= 3 && @view(bytes[1:3]) == utf8_byte_order_mark &&
		throw(EncodingViolation(file, "UTF-8 byte order mark present"))
	carriage_return = findfirst(==(0x0d), bytes)
	carriage_return === nothing ||
		throw(EncodingViolation(file, "carriage return at byte $(carriage_return); policy is LF"))
	isvalid(String(copy(bytes))) ||
		throw(EncodingViolation(file, "not well-formed UTF-8"))
	nothing
end

function read_source_text(path::AbstractString)::String
	bytes = read(path)
	check_encoding(bytes, basename(path))
	String(bytes)
end

function line_starts(text::AbstractString)::Vector{Int}
	starts = Int[1]
	for position in findall(==('\n'), text)
		push!(starts, position + 1)
	end
	starts
end

line_count(text::AbstractString)::Int = length(line_starts(text))

"""
	line_bounds(text, starts, line)

Half-open byte interval of `line`, excluding its terminating newline.
"""
function line_bounds(text::AbstractString, starts::Vector{Int}, line::Int)::Tuple{Int, Int}
	1 <= line <= length(starts) ||
		error("line $(line) out of range; file has $(length(starts)) lines")
	start_byte = starts[line]
	end_byte = line < length(starts) ? starts[line + 1] - 1 : ncodeunits(text) + 1
	(start_byte, end_byte)
end
