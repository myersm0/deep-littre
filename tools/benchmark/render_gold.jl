using ArgParse
using DeepLittre: Source, Census, Adjudication

const repository_root = normpath(joinpath(@__DIR__, "..", ".."))
const display_width = 88

function settings()
	specification = ArgParseSettings()

	@add_arg_table! specification begin
		"source_dir"
			required = true
		"gold_dir"
			help = "store root holding the committed shards"
			required = true
		"--pass"
			default = "decomposition"
		"--patches"
			default = joinpath(repository_root, "patches", "patches.toml")
		"--outcome"
			help = "show only this outcome"
			default = ""
	end

	return parse_args(specification)
end

function print_wrapped(indent::AbstractString, text::AbstractString)
	line = indent
	for word in split(text)
		if length(line) + length(word) + 1 > display_width && length(line) > length(indent)
			println(line)
			line = indent
		end
		line = line == indent ? line * word : line * " " * word
	end
	length(line) > length(indent) && println(line)
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

function report(item, record)
	nature = join(item.entry_nature, ", ")
	rubrique = isnothing(item.rubrique) ? "" : "  [$(item.rubrique)]"
	println("$(item.headword)  ($(nature))  $(Census.kind_name(item.block.kind))$(rubrique)")
	println("  $(record.outcome)")
	print_wrapped("    ", annotated(item.projection.text, record))
	for assertion in record.assertions
		for constituent in assertion.constituents
			text = slice(item.projection.text, constituent.span)
			println("    $(rpad(constituent.name, 6))  $(repr(String(text)))")
		end
	end
	for residual in record.residuals
		println("    resid.  $(repr(String(slice(item.projection.text, residual))))")
	end
	isempty(record.notes) || println("    note    ", record.notes)
	return nothing
end

function tally(records)
	outcome_counts = Dict{Symbol, Int}()
	nodes = 0
	glossed = 0
	for record in records
		outcome_counts[record.outcome] = get(outcome_counts, record.outcome, 0) + 1
		for assertion in record.assertions
			nodes += 1
			any(part -> part.name == "gloss", assertion.constituents) && (glossed += 1)
		end
	end
	println("\n", "─"^display_width)
	for outcome in Adjudication.outcomes
		println("  $(rpad(outcome, 12)) $(get(outcome_counts, outcome, 0))")
	end
	println("  $(rpad("nodes", 12)) $(nodes)")
	println("  $(rpad("with gloss", 12)) $(glossed)")
	println("  $(rpad("no gloss", 12)) $(nodes - glossed)")
	return nothing
end

function main()
	arguments = settings()
	pass = Adjudication.pass_definition(arguments["pass"])
	isnothing(pass) && error("unknown pass $(arguments["pass"])")

	documents = Source.read_corpus(arguments["source_dir"]; patches_path = arguments["patches"])
	harness = Adjudication.Harness(
		documents, Census.census(documents), Adjudication.Store(arguments["gold_dir"]),
	)
	records = Adjudication.read_pass(harness.store, pass.pass)
	isempty(arguments["outcome"]) ||
		filter!(record -> String(record.outcome) == arguments["outcome"], records)

	for (rank, record) in enumerate(records)
		block = Adjudication.target_block!(harness, record, pass)
		println("\n", "─"^display_width)
		print("[$(rank)/$(length(records))] ")
		if isnothing(block)
			println("STALE  $(record.record_id)  $(record.source)")
			continue
		end
		report(Adjudication.adjudication_item(harness, block, ""), record)
	end
	tally(records)
	return nothing
end

main()
