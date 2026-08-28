function write_json_string(io::IO, text::AbstractString)
	write(io, '"')
	for character in text
		if character == '"'
			write(io, "\\\"")
		elseif character == '\\'
			write(io, "\\\\")
		elseif character == '\n'
			write(io, "\\n")
		elseif character == '\r'
			write(io, "\\r")
		elseif character == '\t'
			write(io, "\\t")
		elseif character < ' '
			write(io, "\\u", string(UInt16(character); base = 16, pad = 4))
		else
			write(io, character)
		end
	end
	write(io, '"')
	nothing
end

write_json(io::IO, value::AbstractString) = write_json_string(io, value)
write_json(io::IO, value::Symbol) = write_json_string(io, String(value))
write_json(io::IO, value::Integer) = write(io, string(value))
write_json(io::IO, value::Bool) = write(io, value ? "true" : "false")
write_json(io::IO, ::Nothing) = write(io, "null")

function write_json(io::IO, values::AbstractVector)
	write(io, '[')
	for (index, value) in enumerate(values)
		index == 1 || write(io, ',')
		write_json(io, value)
	end
	write(io, ']')
	nothing
end

mutable struct ObjectWriter
	io::IO
	started::Bool
end

function object(build, io::IO)
	write(io, '{')
	build(ObjectWriter(io, false))
	write(io, '}')
	nothing
end

function field!(writer::ObjectWriter, key::AbstractString, value)
	writer.started && write(writer.io, ',')
	write_json_string(writer.io, key)
	write(writer.io, ':')
	write_json(writer.io, value)
	writer.started = true
	nothing
end

write_json(io::IO, span::RawSpan) = object(io) do writer
	field!(writer, "file", span.file)
	field!(writer, "start_byte", span.start_byte)
	field!(writer, "end_byte", span.end_byte)
end

write_json(io::IO, span::ProjectedSpan) = object(io) do writer
	field!(writer, "start_byte", span.start_byte)
	field!(writer, "end_byte", span.end_byte)
end

write_json(io::IO, constituent::Constituent) = object(io) do writer
	field!(writer, "name", constituent.name)
	field!(writer, "span", constituent.span)
end

write_json(io::IO, assertion::NodeAssertion) = object(io) do writer
	field!(writer, "node_id", assertion.node_id)
	field!(writer, "node_type", node_type_name(assertion.node_type))
	field!(writer, "span", assertion.span)
	field!(writer, "constituents", assertion.constituents)
end

write_json(io::IO, assertion::ScopeAssertion) = object(io) do writer
	field!(writer, "marker", assertion.marker)
	field!(writer, "target", assertion.target)
end

write_json(io::IO, record::ExaminationRecord) = object(io) do writer
	field!(writer, "record_id", record.record_id)
	field!(writer, "pass", record.pass)
	field!(writer, "pass_version", record.pass_version)
	field!(writer, "source", record.source)
	field!(writer, "surface_sha256", record.surface_sha256)
	field!(writer, "outcome", record.outcome)
	field!(writer, "assertions", record.assertions)
	field!(writer, "scopes", record.scopes)
	field!(writer, "residuals", record.residuals)
	field!(writer, "decision_procedure", record.decision_procedure)
	field!(writer, "decision_reference", record.decision_reference)
	field!(writer, "created", record.created)
	field!(writer, "notes", record.notes)
end

function canonical_json(value)::String
	buffer = IOBuffer()
	write_json(buffer, value)
	String(take!(buffer))
end
