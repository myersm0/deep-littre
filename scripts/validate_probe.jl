#!/usr/bin/env julia

# The probe is not expected to validate clean: it pairs each construct with a
# control, and roughly a third of its entries are invalid by design. The gate
# is that each entry's verdict matches the committed table, so a change in the
# vendored schema shows up as a flipped verdict rather than a changed count.

module ValidateProbe

const schema_path = get(ENV, "lex0_rng", joinpath(@__DIR__, "..", "vendor", "tei-lex0-0.9.5", "lex-0.rng"))
const jing_jar = get(ENV, "jing_jar", joinpath(@__DIR__, "..", "vendor", "jing.jar"))
const probe_path = get(ENV, "probe_xml", joinpath(@__DIR__, "..", "test", "probe_lex0.xml"))
const expected_path = get(ENV, "probe_expected", joinpath(@__DIR__, "..", "test", "probe_expected.tsv"))

const entry_pattern = r"<entry\s+xml:id=\"([\w.]+)\""
const message_pattern = r":(\d+):\d+:\s*(?:fatal)?\s*error:"

struct EntrySpan
	id::String
	first_line::Int
	last_line::Int
end

function entry_spans(path::AbstractString)::Vector{EntrySpan}
	spans = EntrySpan[]
	open_id = ""
	open_line = 0
	for (number, line) in enumerate(eachline(path))
		matched = match(entry_pattern, line)
		if matched !== nothing
			open_id = matched.captures[1]
			open_line = number
		end
		if !isempty(open_id) && occursin("</entry>", line)
			push!(spans, EntrySpan(open_id, open_line, number))
			open_id = ""
		end
	end
	spans
end

function error_lines(path::AbstractString)::Vector{Int}
	buffer = IOBuffer()
	command = `java -jar $jing_jar $schema_path $path`
	process = run(pipeline(ignorestatus(command); stdout = buffer, stderr = buffer))
	output = String(take!(buffer))
	process.exitcode > 1 && error("jing failed (exit $(process.exitcode)):\n$(first(output, 1000))")
	[parse(Int, m.captures[1]) for m in eachmatch(message_pattern, output)]
end

function verdicts(path::AbstractString)::Vector{Pair{String, String}}
	lines = error_lines(path)
	[
		span.id => any(line -> span.first_line <= line <= span.last_line, lines) ? "invalid" : "valid"
		for span in entry_spans(path)
	]
end

function expected_verdicts(path::AbstractString)::Dict{String, String}
	table = Dict{String, String}()
	for (index, line) in enumerate(eachline(path))
		index == 1 && continue
		fields = split(line, '\t')
		length(fields) == 2 && (table[String(fields[1])] = String(strip(fields[2])))
	end
	table
end

function main()::Int
	observed = verdicts(probe_path)
	expected = expected_verdicts(expected_path)

	mismatches = Tuple{String, String, String}[]
	for (id, verdict) in observed
		want = get(expected, id, "missing")
		want == verdict || push!(mismatches, (id, want, verdict))
	end
	for id in setdiff(keys(expected), first.(observed))
		push!(mismatches, (id, expected[id], "absent"))
	end

	println("$(length(observed)) probe entries, $(count(pair -> pair.second == "invalid", observed)) invalid by design")
	if isempty(mismatches)
		println("all verdicts match $(basename(expected_path))")
		return 0
	end
	println(stderr, "probe verdicts changed:")
	for (id, want, got) in sort(mismatches)
		println(stderr, "  $(rpad(id, 12)) expected $(rpad(want, 8)) observed $(got)")
	end
	println(stderr, "the vendored schema or the probe changed; re-adjudicate before updating the table")
	1
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
	exit(ValidateProbe.main())
end
