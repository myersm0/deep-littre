using ArgParse
using DeepLittre: Source, Census, Adjudication

const repository_root = normpath(joinpath(@__DIR__, "..", ".."))

include("annotation.jl")

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

function report(item, record)
	nature = join(item.entry_nature, ", ")
	rubrique = isnothing(item.rubrique) ? "" : "  [$(item.rubrique)]"
	println("$(item.headword)  ($(nature))  $(Census.kind_name(item.block.kind))$(rubrique)")
	println("  $(record.outcome)")
	print_wrapped(stdout, "    ", annotated(item.projection.text, record))
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
