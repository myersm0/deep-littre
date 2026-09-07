struct EncodingViolation <: Exception
	file::String
	reason::String
end

Base.showerror(io::IO, violation::EncodingViolation) =
	print(io, "encoding policy violation in ", violation.file, ": ", violation.reason)

encoding_error(file::AbstractString, reason) = throw(EncodingViolation(file, reason))

const utf8_byte_order_mark = UInt8[0xef, 0xbb, 0xbf]

has_byte_order_mark(bytes::Vector{UInt8})::Bool =
	length(bytes) >= 3 && @view(bytes[1:3]) == utf8_byte_order_mark

function check_encoding(bytes::Vector{UInt8}, file::AbstractString)
	has_byte_order_mark(bytes) && encoding_error(file, "UTF-8 byte order mark present")
	carriage_return = findfirst(==(0x0d), bytes)
	if !isnothing(carriage_return)
		encoding_error(file, "carriage return at byte $(carriage_return); policy is LF")
	end
	isvalid(String(copy(bytes))) || encoding_error(file, "not well-formed UTF-8")
	return nothing
end

function read_source_text(path::AbstractString)::String
	bytes = read(path)
	check_encoding(bytes, basename(path))
	return String(bytes)
end

line_starts(text::AbstractString)::Vector{Int} = [1; findall(==('\n'), text) .+ 1]

line_count(text::AbstractString)::Int = length(line_starts(text))

"""
    line_bounds(text, starts, line)

Half-open byte interval of `line`, excluding its terminating newline.
"""
function line_bounds(
	text::AbstractString, starts::Vector{Int}, line::Int,
)::Tuple{Int, Int}
	if line ∉ eachindex(starts)
		error("line $(line) out of range; file has $(length(starts)) lines")
	end
	start_byte = starts[line]
	end_byte = line < length(starts) ? starts[line + 1] - 1 : ncodeunits(text) + 1
	return (start_byte, end_byte)
end
