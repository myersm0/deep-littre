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
		"--role"
			required = true
		"--frame"
			required = true
		"--allow-dirty"
			action = :store_true
		"--patches"
			default = joinpath(repository_root, "patches", "patches.toml")
		"--store"
			default = joinpath(repository_root, "data", "adjudication")
		"--output-dir"
			default = joinpath(repository_root, "benchmark", "samples")
	end

	return parse_args(specification)
end

const roles = ("development", "protected", "final")
const frames = ("population", "challenge", "cross_pass_core")

function checked(value, permitted, name)
	value in permitted ||
		error("$(name) must be one of $(join(permitted, ", ")); got $(repr(value))")
	return value
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

function checked_sample_id(given, pass, n, seed)
	isnothing(given) && return "$(pass.pass)_population_n$(n)_seed$(seed)"
	startswith(given, pass.pass) ||
		error("sample id $(repr(given)) does not name pass $(pass.pass)")
	return given
end

function main()
	arguments = settings()
	role = checked(arguments["role"], roles, "--role")
	frame = checked(arguments["frame"], frames, "--frame")

	documents = Source.read_corpus(
		arguments["source_dir"];
		patches_path = arguments["patches"],
	)

	corpus = Census.census(documents)

	pass = Adjudication.pass_definition(arguments["pass"])
	isnothing(pass) && error("unknown adjudication pass: $(arguments["pass"])")

	population = Adjudication.eligible(pass, corpus)
	population_size = length(population)
	n = arguments["n"]

	0 < n <= population_size ||
		error("sample size $n is invalid for population of $population_size blocks")

	seed = arguments["seed"]
	rng = MersenneTwister(seed)
	selected = population[randperm(rng, population_size)[1:n]]

	sample_id = checked_sample_id(arguments["sample-id"], pass, n, seed)

	dirty = !isempty(git_value(`git status --porcelain`))
	if dirty && role != "development" && !arguments["allow-dirty"]
		error("refusing to draw a $(role) sample from a dirty working tree")
	end

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

	items = [
		Adjudication.adjudication_item(
			harness, block, "$(sample_id):$(lpad(index, 4, '0'))",
		)
		for (index, block) in enumerate(selected)
	]

	open(surfaces_path, "w") do io
		for item in items
			println(io, Adjudication.surface_json(pass, item))
		end
	end

	open(membership_path, "w") do io
		println(io, join([
			"rank",
			"item_id",
			"source_id",
			"entry_id",
			"headword",
			"kind",
			"file",
			"start_byte",
			"end_byte",
			"surface_sha256",
		], '\t'))

		for (index, (block, item)) in enumerate(zip(selected, items))
			println(io, join([
				index,
				item.item_id,
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
		"role" => role,
		"frame" => frame,
		"design" => "simple_random_without_replacement",
		"sampling_unit" => "eligible_block",
		"sample_size" => n,
		"seed" => seed,
		"rng" => "MersenneTwister/randperm",
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
		"repository_dirty" => dirty,
		"julia_version" => string(VERSION),
	)

	open(manifest_path, "w") do io
		TOML.print(io, manifest; sorted = true)
	end

	println("sample:          $sample_id  ($(frame), $(role))")
	println("pass:            $(pass.pass) v$(pass.pass_version)")
	println("population:      $(pass.population) v$(pass.population_version)")
	println("population size: $population_size")
	println("population hash: $(Census.population_hash(population))")
	println("sample size:     $n")
	println("sample hash:     $(Census.population_hash(selected))")
	println("output:          $output_dir")
end

main()
