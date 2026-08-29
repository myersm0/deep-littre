#!/usr/bin/env julia

# Validates a rendered corpus against the pinned TEI Lex-0 schema as a complete document and
# entry by entry, and checks the validator harness itself against the committed probe. A probe disagreement means the harness is
# wrong, not the corpus, so the probe runs first and a mismatch aborts.
#
#   julia --project=. bin/validate_lex0.jl data/littre.tei.xml
#   julia --project=. bin/validate_lex0.jl data/littre.tei.xml --baseline test/lex0_baseline.tsv

module ValidateLex0

println("== load validation environment")
flush(stdout)
load_started = time_ns()
using ArgParse
using XML
println("   complete in ", round((time_ns() - load_started) / 1e9; digits = 2), "s")
flush(stdout)

const repository_root = normpath(joinpath(@__DIR__, ".."))
const schema_path = joinpath(repository_root, "vendor", "tei-lex0-0.9.5", "lex-0.rng")
const jing_path = joinpath(repository_root, "vendor", "jing.jar")

function settings()
	specification = ArgParseSettings(
		prog = "validate_lex0",
		description = "Per-entry TEI Lex-0 validation with the committed probe as arbiter",
	)
	@add_arg_table! specification begin
		"corpus"
			help = "rendered TEI corpus"
			required = true
		"--gate"
			help = "fail if more than this many entries are invalid"
			arg_type = Int
			default = nothing
		"--baseline"
			help = "write a baseline TSV to this path"
			arg_type = String
			default = nothing
		"--probe"
			help = "probe corpus"
			arg_type = String
			default = joinpath(repository_root, "test", "probe_lex0.xml")
		"--expected"
			help = "expected probe verdicts"
			arg_type = String
			default = joinpath(repository_root, "test", "probe_expected.tsv")
	end
	parse_args(specification)
end

document_prologue(text::AbstractString)::String = text[1:(first(findfirst("<body>", text)) - 1)] * "<body>\n"

function find_element(node::XML.FlatNode, name::AbstractString)::Union{Nothing, XML.FlatNode}
	for child in XML.children(node)
		XML.nodetype(child) == XML.Element || continue
		XML.tag(child) == name && return child
		found = find_element(child, name)
		found === nothing || return found
	end
	nothing
end

function entry_texts(text::AbstractString)::Vector{Tuple{String, String}}
	document = XML.parse(XML.FlatNode, text)
	body = find_element(document, "body")
	body === nothing && error("rendered TEI has no <body>")
	entries = Tuple{String, String}[]
	for child in XML.children(body)
		XML.nodetype(child) == XML.Element && XML.tag(child) == "entry" || continue
		fragment = String(XML.sourcetext(child))
		identifier = get(child, "xml:id", "?")
		push!(entries, (identifier, fragment))
	end
	entries
end

function jing(paths::Vector{String})::Vector{String}
	output = IOBuffer()
	try
		run(pipeline(`java -jar $(jing_path) $(schema_path) $(paths)`; stdout = output, stderr = output))
	catch
	end
	filter(!isempty, strip.(split(String(take!(output)), '\n')))
end

validate_path(path::AbstractString)::Vector{String} = jing([String(path)])

# One JVM start and one schema compile dominate a single-file run, so per-entry invocation costs
# roughly a hundred times what the validation itself does. jing prefixes every diagnostic with its
# file, so a batch keeps per-entry attribution.
const batch_size = 500

function attribute_errors(directory::AbstractString, count::Int)::Vector{Vector{String}}
	paths = [joinpath(directory, string(index, ".xml")) for index in 1:count]
	errors = [String[] for _ in 1:count]
	lines = jing(paths)
	# A not-well-formed document is fatal to the whole batch, and jing stops there. Falling back to
	# one file at a time keeps every later entry from being scored valid by silence.
	if any(line -> occursin("fatal:", line), lines)
		@warn "a batch member is not well-formed; falling back to per-file validation" count
		return [validate_path(path) for path in paths]
	end
	for line in lines
		marker = findfirst(".xml:", line)
		marker === nothing && continue
		name = basename(line[1:(last(marker) - 1)])
		index = tryparse(Int, name[1:(end - length(".xml"))])
		index === nothing || push!(errors[index], line)
	end
	errors
end

function validate_batch(prologue::AbstractString, entries)::Vector{Vector{String}}
	directory = mktempdir()
	try
		for (index, (_, fragment)) in enumerate(entries)
			open(joinpath(directory, string(index, ".xml")), "w") do handle
				write(handle, prologue, fragment, "\n</body>\n</text>\n</TEI>\n")
			end
		end
		attribute_errors(directory, length(entries))
	finally
		rm(directory; recursive = true, force = true)
	end
end

function verdicts(
	path::AbstractString; progress = nothing,
)::Vector{Tuple{String, Bool, Vector{String}}}
	text = read(path, String)
	prologue = document_prologue(text)
	entries = entry_texts(text)
	results = Tuple{String, Bool, Vector{String}}[]
	for start in 1:batch_size:length(entries)
		batch = entries[start:min(start + batch_size - 1, length(entries))]
		for ((identifier, _), errors) in zip(batch, validate_batch(prologue, batch))
			push!(results, (identifier, isempty(errors), errors))
		end
		progress === nothing || progress(length(results), length(entries))
	end
	results
end

function run_probe(probe::AbstractString, expected_path::AbstractString)::Bool
	expected = Dict{String, String}()
	for (index, line) in enumerate(eachline(expected_path))
		index == 1 && continue
		fields = split(strip(line), '\t')
		length(fields) >= 2 && (expected[fields[1]] = fields[2])
	end
	agreed = true
	for (identifier, valid, _) in verdicts(probe)
		wanted = get(expected, identifier, nothing)
		wanted === nothing && continue
		observed = valid ? "valid" : "invalid"
		if observed != wanted
			agreed = false
			println("probe disagreement: ", identifier, " expected ", wanted, ", observed ", observed)
		end
	end
	agreed
end

function main()
	arguments = settings()

	println("== probe")
	if !run_probe(arguments["probe"], arguments["expected"])
		println("the validator harness disagrees with the committed probe; corpus results withheld")
		return 2
	end
	println("probe agrees with expected verdicts")

	println("\n== complete document")
	document_elapsed = @elapsed document_errors = validate_path(arguments["corpus"])
	if isempty(document_errors)
		println("valid in ", round(document_elapsed; digits = 2), "s")
	else
		println("invalid after ", round(document_elapsed; digits = 2), "s")
		for line in first(document_errors, min(20, length(document_errors)))
			println("  ", line)
		end
	end

	println("\n== corpus entries")
	entries_elapsed = @elapsed results = verdicts(arguments["corpus"]; progress = function (done, total)
		total > batch_size && print("\r  ", done, " / ", total)
		done == total && total > batch_size && println()
	end)
	println("entry validation complete in ", round(entries_elapsed; digits = 2), "s")
	valid = count(entry -> entry[2], results)
	invalid = length(results) - valid
	println("total   ", length(results))
	println("valid   ", valid)
	println("invalid ", invalid)

	signatures = Dict{String, Int}()
	for (_, ok, errors) in results
		ok && continue
		for line in errors
			signature = replace(line, r"^.*error: " => "")
			signatures[signature] = get(signatures, signature, 0) + 1
		end
	end
	for (signature, total) in first(sort(collect(signatures); by = last, rev = true), 15)
		println("  ", lpad(total, 6), "  ", first(signature, 100))
	end

	if arguments["baseline"] !== nothing
		open(arguments["baseline"], "w") do handle
			println(handle, "total\t", length(results))
			println(handle, "valid\t", valid)
			println(handle, "invalid\t", invalid)
			println(handle, "# ranked error signatures")
			for (signature, total) in sort(collect(signatures); by = last, rev = true)
				println(handle, total, "\t", signature)
			end
			println(handle, "# document-level errors")
			foreach(error -> println(handle, error), document_errors)
			println(handle, "# invalid entries")
			for (identifier, ok, _) in results
				ok || println(handle, identifier)
			end
		end
	end

	gate = arguments["gate"]
	if !isempty(document_errors)
		println("\ngate: complete TEI document is invalid")
		return 1
	end
	if gate !== nothing && invalid > gate
		println("\ngate: $(invalid) invalid entries exceeds the committed floor of $(gate)")
		return 1
	end
	(gate === nothing && invalid > 0) ? 1 : 0
end

end

exit(ValidateLex0.main())
