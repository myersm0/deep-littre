#!/usr/bin/env julia

# Coverage and review reporting over the current adjudication state. Low structural coverage is
# the expected intermediate state of the rewrite, not a defect: absence of a record means no pass
# has looked, and nothing licenses a derived sense until one has.
#
#   julia --project=. bin/report.jl data/source
#   julia --project=. bin/report.jl data/source --review data/review.tsv

module Report

using ArgParse
using DeepLittre
using DeepLittre: Source, Census, Adjudication, Resolve

function settings()
	repository_root = normpath(joinpath(@__DIR__, ".."))
	specification = ArgParseSettings(
		prog = "report", description = "Adjudication coverage and review findings",
	)
	@add_arg_table! specification begin
		"source_dir"
			help = "directory holding the XMLittré source files"
			required = true
		"--patches"
			arg_type = String
			default = joinpath(repository_root, "patches", "patches.toml")
		"--store"
			arg_type = String
			default = joinpath(repository_root, "data", "adjudication")
		"--review"
			help = "write review findings to this TSV"
			arg_type = String
			default = nothing
	end
	parse_args(specification)
end

function percentage(part::Int, whole::Int)::String
	whole == 0 ? "  n/a" : string(lpad(round(100 * part / whole; digits = 2), 6), "%")
end

function main()
	arguments = settings()

	documents = Source.read_corpus(
		arguments["source_dir"];
		patches_path = isfile(arguments["patches"]) ? arguments["patches"] : nothing,
	)
	corpus = Census.census(documents)
	harness = Adjudication.Harness(documents, corpus, Adjudication.Store(arguments["store"]))
	resolved = Resolve.resolve(harness)

	println("== census")
	blocks = Census.all_blocks(corpus)
	println("entries        ", length(Census.all_entries(corpus)))
	println("blocks         ", length(blocks))
	for (name, total) in sort(collect(Census.counts(corpus)); by = first)
		println("  ", rpad(name, 18), total)
	end

	println("\n== coverage")
	for record in resolved.coverage
		println(record.pass, " v", record.pass_version, " over ", record.population,
			" v", record.population_version)
		println("  population   ", record.population_size, "  ", record.population_hash[1:16])
		println("  examined     ", lpad(record.examined, 8), percentage(record.examined, record.population_size))
		println("  positive     ", lpad(record.positive, 8))
		println("  negative     ", lpad(record.negative, 8))
		println("  unresolved   ", lpad(record.unresolved, 8))
		println("  stale  ", lpad(record.stale, 8))
	end

	println("\n== derivation")
	types = Union{Nothing, Adjudication.NodeType}[]
	function walk(nodes)
		for node in nodes
			push!(types, node.node_type)
			walk(node.children)
		end
	end
	foreach(entry -> walk(entry.nodes), resolved.entries)
	derived = count(node_type -> node_type isa Adjudication.Sense, types)
	asserted = count(node_type -> node_type isa Adjudication.SubLemma ||
		node_type isa Adjudication.VoiceVariant, types)
	println("nodes          ", length(types))
	println("derived Sense  ", lpad(derived, 8), percentage(derived, length(types)))
	println("asserted       ", lpad(asserted, 8))
	println("underdetermined", lpad(count(isnothing, types), 8),
		percentage(count(isnothing, types), length(types)))

	println("\n== review")
	if isempty(resolved.review)
		println("no findings")
	else
		tally = Dict{String, Int}()
		for finding in resolved.review
			tally[finding.category] = get(tally, finding.category, 0) + 1
		end
		for (category, total) in sort(collect(tally); by = last, rev = true)
			println("  ", lpad(total, 6), "  ", category)
		end
		for finding in first(resolved.review, 20)
			println("    ", finding.category, "  ", finding.span.file, ":",
				finding.span.start_byte, "  ", first(finding.detail, 90))
		end
	end

	if arguments["review"] !== nothing
		open(arguments["review"], "w") do handle
			println(handle, join(["category", "detail", "file", "start_byte", "end_byte"], '\t'))
			for finding in resolved.review
				println(handle, join([
					finding.category, finding.detail,
					finding.span.file, finding.span.start_byte, finding.span.end_byte,
				], '\t'))
			end
		end
	end

	isempty(resolved.review) ? 0 : 1
end

end

exit(Report.main())
