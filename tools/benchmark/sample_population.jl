using ArgParse
using Dates
using Random
using SHA
using TOML
using DeepLittre
using DeepLittre: Source, Census, Adjudication

const repository_root = normpath(joinpath(@__DIR__, "..", ".."))

function settings()
	specification = ArgParseSettings()

	@add_arg_table! specification begin
		"source_dir"
			required = true
		"--pass"
			default = "sublemma"
		"--n"
			arg_type = Int
			default = 100
		"--seed"
			arg_type = Int
			default = 20260906
		"--sample-id"
			default = nothing
		"--patches"
			default = joinpath(repository_root, "patches", "patches.toml")
		"--store"
			default = joinpath(repository_root, "data", "adjudication")
		"--output-dir"
			default = joinpath(repository_root, "benchmark", "samples")
	end

	parse_args(specification)
end

function git_value(command)
	try
		cd(repository_root) do
			strip(read(command, String))
		end
	catch
		"unknown"
	end
end

const trivial_rules = [
	:empty => isempty,
	:century_marker => text -> occursin(r"^[IVXLC]+e\s+s\.$", text),
	:supplement_opener => text -> occursin(r"^\S+\.\s+Ajoutez\s*:$", text),
]

function trivial_rule(text)
	for (name, rule) in trivial_rules
		rule(text) && return name
	end
	return nothing
end

function main()
	arguments = settings()

	documents = Source.read_corpus(
		arguments["source_dir"];
		patches_path = arguments["patches"],
	)

	corpus = Census.census(documents)

	pass = Adjudication.pass_definition(arguments["pass"])
	pass === nothing && error("unknown adjudication pass: $(arguments["pass"])")

	population = Adjudication.eligible(pass, corpus)
	population_size = length(population)
	n = arguments["n"]

	0 < n <= population_size ||
		error("sample size $n is invalid for population of $population_size blocks")

	seed = arguments["seed"]
	rng = MersenneTwister(seed)
	selected = population[randperm(rng, population_size)[1:n]]

	sample_id = something(
		arguments["sample-id"],
		"$(pass.pass)_population_n$(n)_seed$(seed)",
	)

	output_dir = joinpath(arguments["output-dir"], sample_id)
	mkpath(output_dir)

	harness = Adjudication.Harness(
		documents,
		corpus,
		Adjudication.Store(arguments["store"]),
	)

	headwords = Dict(
		entry.source_id => entry.headword
		for entry in Census.all_entries(corpus)
	)

	surfaces_path = joinpath(output_dir, "surfaces.jsonl")
	membership_path = joinpath(output_dir, "membership.tsv")
	manifest_path = joinpath(output_dir, "manifest.toml")

	open(surfaces_path, "w") do io
		for (index, block) in enumerate(selected)
			item_id = "$(sample_id):$(lpad(index, 4, '0'))"
			item = Adjudication.adjudication_item(harness, block, item_id)
			println(io, Adjudication.surface_json(pass, item))
		end
	end

	open(membership_path, "w") do io
		println(io, join([
			"rank",
			"source_id",
			"entry_id",
			"headword",
			"kind",
			"file",
			"start_byte",
			"end_byte",
			"surface_sha256",
		], '\t'))

		for (index, block) in enumerate(selected)
			item_id = "$(sample_id):$(lpad(index, 4, '0'))"
			item = Adjudication.adjudication_item(harness, block, item_id)

			println(io, join([
				index,
				block.source_id,
				block.entry_id,
				get(headwords, block.entry_id, ""),
				Census.kind_name(block.kind),
				block.raw_span.file,
				block.raw_span.start_byte,
				block.raw_span.end_byte,
				Adjudication.surface_sha256(item),
			], '\t'))
		end
	end

	manifest = Dict(
		"sample_id" => sample_id,
		"created_utc" => string(now(UTC)),
		"purpose" => "development",
		"sampling" => "population",
		"design" => "simple_random_without_replacement",
		"sample_size" => n,
		"seed" => seed,
		"inclusion_probability" => n / population_size,
		"pass" => pass.pass,
		"pass_version" => pass.pass_version,
		"population" => pass.population,
		"population_version" => pass.population_version,
		"population_size" => population_size,
		"population_hash" => Census.population_hash(population),
		"projection" => pass.projection,
		"projection_version" => pass.projection_version,
		"sample_hash" => Census.population_hash(selected),
		"patched_source_sha256" => Source.patched_corpus_sha256(documents),
		"repository_commit" => git_value(`git rev-parse HEAD`),
		"repository_dirty" => !isempty(git_value(`git status --porcelain`)),
		"julia_version" => string(VERSION),
	)

	open(manifest_path, "w") do io
		TOML.print(io, manifest; sorted = true)
	end

	println("sample:		  $sample_id")
	println("pass:			$(pass.pass) v$(pass.pass_version)")
	println("population:	  $(pass.population) v$(pass.population_version)")
	println("population size: $population_size")
	println("population hash: $(Census.population_hash(population))")
	println("sample size:	 $n")
	println("sample hash:	 $(Census.population_hash(selected))")
	println("output:		  $output_dir")
end

main()
