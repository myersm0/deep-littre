const display_width = 88

function print_wrapped(io::IO, indent::AbstractString, text::AbstractString)
	line = indent
	for word in split(text)
		if length(line) + length(word) + 1 > display_width && length(line) > length(indent)
			println(io, line)
			line = indent
		end
		line = line == indent ? line * word : line * " " * word
	end
	length(line) > length(indent) && println(io, line)
	return nothing
end

slice(text::AbstractString, span) =
	SubString(text, span.start_byte, prevind(text, span.end_byte))

function marks(record)
	found = Tuple{Int, Bool, Int, String}[]
	for assertion in record.assertions
		push!(found, (assertion.span.start_byte, true, 1, "⟦"))
		push!(found, (assertion.span.end_byte, false, 1, "⟧"))
		for constituent in assertion.constituents
			push!(found, (constituent.span.start_byte, true, 2, "[$(constituent.name) "))
			push!(found, (constituent.span.end_byte, false, 2, "]"))
		end
	end
	for residual in record.residuals
		push!(found, (residual.start_byte, true, 0, "«"))
		push!(found, (residual.end_byte, false, 0, "»"))
	end
	return sort(found; by = mark -> (mark[1], mark[2], mark[2] ? mark[3] : -mark[3]))
end

function annotated(text::AbstractString, record)
	buffer = IOBuffer()
	position = 1
	for (at, _, _, mark) in marks(record)
		print(buffer, SubString(text, position, prevind(text, at)), mark)
		position = at
	end
	position <= ncodeunits(text) && print(buffer, SubString(text, position))
	return String(take!(buffer))
end
