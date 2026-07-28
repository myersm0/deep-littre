#!/usr/bin/env julia

# Builds the release artifacts and refuses to package anything that regresses
# past the committed baseline. The gate reads its floor from the baseline file
# rather than a literal, so the number lives in one place.

module Release

using TOML

const repo_root = normpath(joinpath(@__DIR__, ".."))
const source_directory = get(ENV, "littre_source", joinpath(repo_root, "data", "source"))
const output_directory = get(ENV, "littre_output", joinpath(repo_root, "data"))
const baseline_path = joinpath(repo_root, "test", "lex0_baseline.tsv")

const corpus_name = "littre.tei.xml"
const database_name = "littre.db"

function baseline_invalid(path::AbstractString)::Int
	isfile(path) || error("missing baseline: $(path); run validate_lex0.jl --baseline first")
	for line in eachline(path)
		fields = split(line, '\t')
		length(fields) == 2 && fields[1] == "invalid" && return parse(Int, fields[2])
	end
	error("no invalid count in $(path)")
end

project_version()::String = TOML.parsefile(joinpath(repo_root, "Project.toml"))["version"]

function step(description::AbstractString, command::Cmd)
	println("\n== $(description)")
	println("   $(command)")
	run(command)
end

function compress(path::AbstractString)::String
	archive = path * ".gz"
	isfile(archive) && rm(archive)
	step("compress $(basename(path))", `gzip --keep --force $(path)`)
	archive
end

function checksums(paths::Vector{String})::String
	manifest = joinpath(output_directory, "SHA256SUMS")
	open(manifest, "w") do io
		for path in paths
			digest = first(split(read(`shasum -a 256 $(path)`, String)))
			println(io, "$(digest)  $(basename(path))")
		end
	end
	manifest
end

function main()::Int
	isdir(source_directory) || error("missing source directory: $(source_directory)")
	mkpath(output_directory)

	version = project_version()
	floor_value = baseline_invalid(baseline_path)
	println("deep-littre v$(version); gate floor $(floor_value) invalid entries")

	corpus = joinpath(output_directory, corpus_name)
	database = joinpath(output_directory, database_name)

	step(
		"build corpus and database",
		`julia --project=$(repo_root) $(joinpath(repo_root, "bin", "run_pipeline.jl")) $(source_directory) $(output_directory)`,
	)
	step(
		"validate against the pinned Lex-0 schema",
		`julia --project=$(repo_root) $(joinpath(repo_root, "scripts", "validate_lex0.jl")) $(corpus) --gate $(floor_value)`,
	)
	step("verify probe verdicts", `julia --project=$(repo_root) $(joinpath(repo_root, "scripts", "validate_probe.jl"))`)

	archives = [compress(corpus), compress(database)]
	manifest = checksums(archives)

	println("\n== release artifacts for v$(version)")
	for path in vcat(archives, manifest)
		println("   $(path)  ($(round(filesize(path) / 1024^2; digits = 1)) MB)")
	end
	println("\nupload with: gh release create v$(version) $(join(vcat(archives, manifest), " "))")
	0
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
	exit(Release.main())
end
