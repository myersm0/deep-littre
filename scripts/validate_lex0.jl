#!/usr/bin/env julia

module ValidateLex0

const schema_path = get(ENV, "lex0_rng", joinpath(@__DIR__, "..", "vendor", "tei-lex0-0.9.5", "lex-0.rng"))
const jing_jar = get(ENV, "jing_jar", joinpath(@__DIR__, "..", "vendor", "jing.jar"))
const chunk_size = parse(Int, get(ENV, "validate_chunk", "4000"))

const wrapper_head = """
<?xml version="1.0" encoding="UTF-8"?>
<TEI xmlns="http://www.tei-c.org/ns/1.0" xml:id="validation-wrapper" type="lex-0">
<teiHeader><fileDesc>
<titleStmt><title>t</title></titleStmt>
<publicationStmt><publisher>p</publisher></publicationStmt>
<sourceDesc><listBibl type="dictionaries"><biblStruct><monogr>
<title level="m">t</title><imprint><publisher>p</publisher><date>2026</date></imprint>
</monogr></biblStruct></listBibl></sourceDesc>
</fileDesc><profileDesc><langUsage>
<language ident="fr" role="objectLanguage">French</language>
</langUsage></profileDesc></teiHeader>
<text><body>
"""

const wrapper_foot = "\n</body></text>\n</TEI>\n"

# jing prints "PATH:line:col: level: message"; attribution keys on basename.
# jing is the sole well-formedness authority: XML.jl 0.3.x accepts mis-nested
# input, so an in-process gate cannot be trusted. jing aborts the remaining
# argument list on the first fatal error, so run_jing re-runs each batch tail
# past a fatal until the whole set is covered. Fatal lines are normalized to a
# single malformed_signature so the not-well-formed population ranks as one row.
const path_pattern = r"^(.*?\.xml):"
const message_pattern = r"^.*?\.xml:\d+:\d+:\s*(?:error|fatal(?:\s+error)?):\s*(.*)$"
const entry_boundary = r"<entry\b|</entry>"
const id_pattern = r"xml:id=\"([^\"]*)\""
const fatal_line = r"^(.*?\.xml):\d+:\d+:\s*fatal"
const malformed_signature = "not well-formed XML"

struct EntryResult
	id::String
	errors::Vector{String}
end

struct Report
	total::Int
	valid::Int
	results::Vector{EntryResult}
	signatures::Vector{Pair{String, Int}}
end

function top_level_entries(corpus_path::String)::Vector{Tuple{String, String}}
	text = read(corpus_path, String)
	entries = Tuple{String, String}[]
	depth = 0
	start = 0
	for m in eachmatch(entry_boundary, text)
		if m.match == "</entry>"
			depth -= 1
			if depth == 0
				fragment = text[start:(m.offset + ncodeunits(m.match) - 1)]
				push!(entries, (extract_id(fragment), fragment))
			end
		else
			depth == 0 && (start = m.offset)
			depth += 1
		end
	end
	entries
end

function extract_id(fragment::AbstractString)::String
	matched = match(id_pattern, fragment)
	matched === nothing ? "" : matched.captures[1]
end

function invoke_jing(paths)
	buffer = IOBuffer()
	command = `java -jar $jing_jar $schema_path $paths`
	process = run(pipeline(ignorestatus(command); stdout = buffer, stderr = buffer))
	output = String(take!(buffer))
	process.exitcode > 1 && error("jing failed (exit $(process.exitcode)) on a batch of $(length(paths)) files:\n$(first(output, 1000))")
	split(output, '\n'; keepempty = false)
end

function fatal_index(lines, paths)::Union{Nothing, Int}
	for line in lines
		matched = match(fatal_line, line)
		matched === nothing && continue
		key = basename(matched.captures[1])
		index = findfirst(path -> basename(path) == key, paths)
		index === nothing || return index
	end
	nothing
end

function run_jing(paths)::Vector{String}
	messages = String[]
	for group in Iterators.partition(collect(paths), chunk_size)
		remaining = collect(group)
		while !isempty(remaining)
			lines = invoke_jing(remaining)
			append!(messages, lines)
			poison = fatal_index(lines, remaining)
			poison === nothing && break
			remaining = remaining[(poison + 1):end]
		end
	end
	messages
end

function group_by_source(messages::Vector{<:AbstractString})::Dict{String, Vector{String}}
	grouped = Dict{String, Vector{String}}()
	for line in messages
		path_match = match(path_pattern, line)
		path_match === nothing && continue
		key = basename(path_match.captures[1])
		signature = if match(fatal_line, line) !== nothing
			malformed_signature
		else
			sig_match = match(message_pattern, line)
			sig_match === nothing ? "unparsed jing output: $(strip(line))" : sig_match.captures[1]
		end
		push!(get!(grouped, key, String[]), signature)
	end
	grouped
end

function rank_signatures(results::Vector{EntryResult})::Vector{Pair{String, Int}}
	counts = Dict{String, Int}()
	for result in results, signature in result.errors
		counts[signature] = get(counts, signature, 0) + 1
	end
	sort(collect(counts); by = pair -> (-pair.second, pair.first))
end

function validate_document(path::String)::Tuple{Bool, Int}
	messages = run_jing([path])
	errors = count(line -> match(message_pattern, line) !== nothing, messages)
	(errors == 0, errors)
end

function validate_per_entry(corpus_path::String)::Report
	entries = top_level_entries(corpus_path)
	directory = mktempdir()
	basename_to_id = Dict{String, String}()
	filenames = String[]
	pre_results = EntryResult[]
	for (index, (id, fragment)) in enumerate(entries)
		label = isempty(id) ? "entry_$(index)" : id
		if !occursin("<entry", fragment)
			push!(pre_results, EntryResult(label, ["split error: fragment contains no entry element"]))
			continue
		end
		name = "$(index).xml"
		write(joinpath(directory, name), string(wrapper_head, fragment, wrapper_foot))
		basename_to_id[name] = label
		push!(filenames, name)
	end

	grouped = group_by_source(run_jing(joinpath.(directory, filenames)))
	results = [EntryResult(basename_to_id[name], get(grouped, name, String[])) for name in filenames]
	append!(results, pre_results)
	rm(directory; recursive = true)

	valid = count(result -> isempty(result.errors), results)
	Report(length(results), valid, results, rank_signatures(results))
end

function print_report(report::Report; io::IO = stdout)
	println(io, "$(report.valid) of $(report.total) entries valid")
	println(io)
	println(io, "ranked error signatures:")
	for (signature, n) in report.signatures
		println(io, "  $(lpad(n, 6))  $(signature)")
	end
end

function write_baseline(report::Report, path::String)
	open(path, "w") do io
		println(io, "total\t$(report.total)")
		println(io, "valid\t$(report.valid)")
		println(io, "invalid\t$(report.total - report.valid)")
		println(io, "# ranked error signatures")
		for (signature, n) in report.signatures
			println(io, "$(n)\t$(signature)")
		end
	end
end

function main(arguments::Vector{String})
	if isempty(arguments)
		println(stderr, "usage: julia validate_lex0.jl <corpus.xml> [--baseline out.tsv] [--gate N]")
		return 2
	end
	corpus = arguments[1]

	whole_ok, whole_errors = validate_document(corpus)
	whole_ok || println(stderr, "whole-document validation reported $(whole_errors) error(s)")

	report = validate_per_entry(corpus)
	print_report(report)

	baseline_index = findfirst(==("--baseline"), arguments)
	baseline_index === nothing || write_baseline(report, arguments[baseline_index + 1])

	gate_index = findfirst(==("--gate"), arguments)
	if gate_index !== nothing
		limit = parse(Int, arguments[gate_index + 1])
		invalid = report.total - report.valid
		if invalid > limit
			println(stderr, "regression: $(invalid) invalid entries exceeds baseline $(limit)")
			return 1
		end
	end
	0
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
	exit(ValidateLex0.main(ARGS))
end
