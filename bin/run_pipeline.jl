#!/usr/bin/env julia

# Deep-Littré v0.3 pipeline: source → census → adjudication state → resolved representation →
# TEI Lex-0 + SQLite.
#
# Building with no adjudication store is a supported mode, not a failure: the result is a coarse
# corpus carrying every explicit XMLittré fact. Adjudications enrich structure monotonically on
# top of that, and never recreate what the source already states.
#
#   julia --project=. bin/run_pipeline.jl data/source data
#   julia --project=. bin/run_pipeline.jl data/source data --strict-adjudications

module Pipeline

using ArgParse
using DeepLittre
using DeepLittre: Source, Census, Adjudication, Resolve, Render

const repository_root = normpath(joinpath(@__DIR__, ".."))

seconds(elapsed) = round(elapsed; digits = 2)
megabytes(bytes) = round(bytes / 1024^2; digits = 2)

function settings()
	specification = ArgParseSettings(
		prog = "run_pipeline",
		description = "Deep-Littré v0.3: source → census → resolve → emit",
	)
	@add_arg_table! specification begin
		"source_dir"
			help = "directory containing the XMLittré source files (a.xml–z.xml)"
			required = true
		"output_dir"
			help = "directory for littre.tei.xml and littre.db"
			required = true
		"--patches"
			help = "patch set, or \"none\" to read the source unpatched"
			arg_type = String
			default = joinpath(repository_root, "patches", "patches.toml")
		"--store"
			help = "adjudication store root"
			arg_type = String
			default = joinpath(repository_root, "data", "adjudication")
		"--strict-adjudications"
			help = "treat any stale adjudication as fatal"
			action = :store_true
		"--coverage"
			help = "write per-pass coverage to this TSV"
			arg_type = String
			default = nothing
		"--review"
			help = "write review findings to this TSV"
			arg_type = String
			default = nothing
		"--build-manifest"
			help = "write build provenance to this TOML file"
			arg_type = String
			dest_name = "build_manifest"
			default = nothing
	end
	parse_args(specification)
end

function write_coverage(path::AbstractString, corpus::Resolve.ResolvedCorpus)
	open(path, "w") do handle
		println(handle, join([
			"pass", "pass_version", "population", "population_version", "population_size",
			"population_hash", "examined", "positive", "negative", "unresolved", "stale",
		], '\t'))
		for record in corpus.coverage
			println(handle, join([
				record.pass, record.pass_version, record.population, record.population_version,
				record.population_size, record.population_hash, record.examined, record.positive,
				record.negative, record.unresolved, record.stale,
			], '\t'))
		end
	end
end

function write_review(path::AbstractString, corpus::Resolve.ResolvedCorpus)
	open(path, "w") do handle
		println(handle, join(["category", "detail", "file", "start_byte", "end_byte"], '\t'))
		for finding in corpus.review
			println(handle, join([
				finding.category, replace(finding.detail, '\t' => ' '),
				finding.span.file, finding.span.start_byte, finding.span.end_byte,
			], '\t'))
		end
	end
end

function write_build_manifest(path::AbstractString, documents::Vector{Source.SourceDocument})
	mkpath(dirname(path))
	open(path, "w") do handle
		println(handle, "patched_source_sha256 = \"$(Source.patched_corpus_sha256(documents))\"")
	end
end

function main()::Int
	arguments = settings()
	isdir(arguments["source_dir"]) || error("missing source directory: $(arguments["source_dir"])")
	mkpath(arguments["output_dir"])

	patches = arguments["patches"] == "none" ? nothing : arguments["patches"]
	patches === nothing ? (@info "building from unpatched source") : (@info "patches" path = patches)

	@info "source"
	source_elapsed = @elapsed documents = Source.read_corpus(
		arguments["source_dir"];
		patches_path = patches,
		progress = (file, bytes, patched, elapsed) -> @info(
			"  read $(rpad(file, 8)) $(lpad(megabytes(bytes), 7)) MB  \
			$(lpad(patched, 3)) patches  $(lpad(seconds(elapsed), 7))s"
		),
	)
	@info "source complete: $(length(documents)) files in $(seconds(source_elapsed))s"

	@info "census"
	census_elapsed = @elapsed corpus = Census.census(
		documents;
		progress = (file, entries, blocks, elapsed) -> @info(
			"  census $(rpad(file, 8)) $(lpad(entries, 6)) entries  \
			$(lpad(blocks, 7)) blocks  $(lpad(seconds(elapsed), 7))s"
		),
	)
	blocks = Census.all_blocks(corpus)
	@info "census complete: $(length(blocks)) blocks in $(seconds(census_elapsed))s"
	@info "census" entries = length(Census.all_entries(corpus)) blocks = length(blocks) population =
		first(Census.population_hash(blocks), 16)
	anomalies = Census.anomalies(corpus)
	isempty(anomalies) || @warn "census anomalies" count = length(anomalies)

	isdir(arguments["store"]) ||
		@info "no adjudication store; building coarsely" path = arguments["store"]
	harness = Adjudication.Harness(documents, corpus, Adjudication.Store(arguments["store"]))

	@info "resolve"
	resolve_elapsed = @elapsed resolved = Resolve.resolve(
		harness;
		strict = arguments["strict-adjudications"],
		progress = (file, entries, elapsed) -> @info(
			"  resolve $(rpad(file, 8)) $(lpad(entries, 6)) entries  $(lpad(seconds(elapsed), 7))s"
		),
	)
	@info "resolve complete: $(length(resolved.entries)) entries in $(seconds(resolve_elapsed))s"
	for record in resolved.coverage
		@info "coverage" pass = record.pass population = record.population_size examined = record.examined positive =
			record.positive negative = record.negative unresolved = record.unresolved stale = record.stale
	end
	isempty(resolved.review) || @warn "review findings" count = length(resolved.review)

	tei_path = joinpath(arguments["output_dir"], "littre.tei.xml")
	@info "emit TEI" path = tei_path
	tei_elapsed = @elapsed Render.render_tei(resolved, tei_path)
	@info "TEI complete in $(seconds(tei_elapsed))s"

	database_path = joinpath(arguments["output_dir"], "littre.db")
	@info "emit SQLite" path = database_path
	database_elapsed = @elapsed Render.render_sqlite(resolved, database_path)
	@info "SQLite complete in $(seconds(database_elapsed))s"

	arguments["coverage"] === nothing || write_coverage(arguments["coverage"], resolved)
	arguments["review"] === nothing || write_review(arguments["review"], resolved)
	build_manifest = get(arguments, "build_manifest", nothing)
	build_manifest === nothing || write_build_manifest(build_manifest, documents)

	@info "done" tei_mb = round(filesize(tei_path) / 1024^2; digits = 2) database_mb =
		round(filesize(database_path) / 1024^2; digits = 2)
	0
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
	exit(Pipeline.main())
end
