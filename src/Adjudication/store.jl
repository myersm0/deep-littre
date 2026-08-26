"""
The authoritative store is text-based and diffable: one canonical JSON object per line, sharded
by pass and source letter. Only this writer serializes committed records.
"""
struct Store
	root::String
end

struct PopulationManifest
	version::Union{Nothing, Int}
	includes::Vector{String}
	excludes::Vector{String}
end

struct PassManifest
	pass_version::Union{Nothing, Int}
	population::Union{Nothing, String}
	population_version::Union{Nothing, Int}
	projection::Union{Nothing, String}
	projection_version::Union{Nothing, Int}
	exhaustive_extraction::Union{Nothing, Bool}
end

struct StoreManifest
	structural_alternative_set_version::Union{Nothing, Int}
	closure_protocol_version::Union{Nothing, Int}
	projections::Dict{String, Union{Nothing, Int}}
	populations::Dict{String, PopulationManifest}
	passes::Dict{String, PassManifest}
end

struct StoreIntegrityError <: Exception
	detail::String
end

Base.showerror(io::IO, failure::StoreIntegrityError) =
	print(io, "adjudication store integrity failure: ", failure.detail)

pass_directory(store::Store, pass::AbstractString)::String = joinpath(store.root, pass)
manifest_path(store::Store)::String = joinpath(store.root, "manifest.toml")

shard_of(record::ExaminationRecord)::String = first(splitext(record.source.file))

shard_path(store::Store, pass::AbstractString, shard::AbstractString)::String =
	joinpath(pass_directory(store, pass), shard * ".jsonl")

function store_pass_directories(store::Store)::Vector{String}
	isdir(store.root) || return String[]
	sort(String[
		name for name in readdir(store.root)
		if isdir(joinpath(store.root, name)) && any(
			endswith(entry, ".jsonl") for entry in readdir(joinpath(store.root, name))
		)
	])
end

store_has_records(store::Store)::Bool = !isempty(store_pass_directories(store))

optional_int(table, key::AbstractString) = haskey(table, key) ? Int(table[key]) : nothing
optional_string(table, key::AbstractString) = haskey(table, key) ? String(table[key]) : nothing

function read_manifest(store::Store)::Union{Nothing, StoreManifest}
	path = manifest_path(store)
	isfile(path) || return nothing
	data = try
		TOML.parsefile(path)
	catch failure
		throw(StoreIntegrityError("cannot read $(path): $(sprint(showerror, failure))"))
	end
	projections = Dict{String, Union{Nothing, Int}}(
		String(name) => optional_int(definition, "version")
		for (name, definition) in get(data, "projections", Dict{String, Any}())
	)
	populations = Dict{String, PopulationManifest}()
	for (name, definition) in get(data, "populations", Dict{String, Any}())
		populations[String(name)] = PopulationManifest(
			optional_int(definition, "version"),
			String[String(value) for value in get(definition, "includes", String[])],
			String[String(value) for value in get(definition, "excludes", String[])],
		)
	end
	passes = Dict{String, PassManifest}()
	for (name, definition) in get(data, "passes", Dict{String, Any}())
		passes[String(name)] = PassManifest(
			optional_int(definition, "pass_version"),
			optional_string(definition, "population"),
			optional_int(definition, "population_version"),
			optional_string(definition, "projection"),
			optional_int(definition, "projection_version"),
			haskey(definition, "exhaustive_extraction") ?
				Bool(definition["exhaustive_extraction"]) : nothing,
		)
	end
	StoreManifest(
		optional_int(data, "structural_alternative_set_version"),
		optional_int(data, "closure_protocol_version"),
		projections,
		populations,
		passes,
	)
end

function replace_atomically(path::AbstractString, contents::AbstractString)
	mkpath(dirname(path))
	staging = path * ".staging"
	open(staging, "w") do handle
		write(handle, contents)
	end
	mv(staging, path; force = true)
	nothing
end

function replace_directory!(path::AbstractString, staging::AbstractString)
	backup = path * ".previous." * string(uuid4())
	if isdir(path)
		mv(path, backup)
	end
	try
		mv(staging, path)
	catch
		isdir(backup) && !ispath(path) && mv(backup, path)
		rethrow()
	end
	isdir(backup) && rm(backup; recursive = true, force = true)
	nothing
end

"""
	write_pass!(store, pass, records)

Regenerate every shard of one pass. Records are sorted by durable anchor so diffs stay local, and
the complete pass directory is replaced from a staged copy so obsolete shards cannot survive.
"""
function record_matches_manifest(record::ExaminationRecord, definition::PassManifest)::Bool
	record.pass_version == definition.pass_version &&
		record.population == definition.population &&
		record.population_version == definition.population_version &&
		record.projection == definition.projection &&
		record.projection_version == definition.projection_version
end

function write_pass!(store::Store, pass::AbstractString, records::Vector{ExaminationRecord})
	manifest = read_manifest(store)
	manifest === nothing && throw(StoreIntegrityError(
		"cannot write pass $(pass) without manifest.toml",
	))
	definition = get(manifest.passes, String(pass), nothing)
	definition === nothing && throw(StoreIntegrityError(
		"cannot write pass $(pass): it is not declared in manifest.toml",
	))
	ordered = sort(records; by = sort_key)
	sharded = Dict{String, Vector{ExaminationRecord}}()
	for record in ordered
		record.pass == pass || error("record for pass $(record.pass) written to pass $(pass)")
		record_matches_manifest(record, definition) || throw(StoreIntegrityError(
			"record $(record.record_id) does not match manifest definition for pass $(pass)",
		))
		push!(get!(sharded, shard_of(record), ExaminationRecord[]), record)
	end
	mkpath(store.root)
	directory = pass_directory(store, pass)
	staging = directory * ".staging." * string(uuid4())
	mkpath(staging)
	try
		for (shard, shard_records) in sharded
			buffer = IOBuffer()
			for record in shard_records
				write_json(buffer, record)
				write(buffer, '\n')
			end
			write_path = joinpath(staging, shard * ".jsonl")
			open(write_path, "w") do handle
				write(handle, String(take!(buffer)))
			end
		end
		replace_directory!(directory, staging)
	catch
		ispath(staging) && rm(staging; recursive = true, force = true)
		rethrow()
	end
	sharded
end

function read_span(entry)::RawSpan
	RawSpan(entry["file"], entry["start_byte"], entry["end_byte"])
end

function read_constituent(entry)::Constituent
	Constituent(entry["name"], read_span(entry["span"]))
end

function read_assertion(entry)::NodeAssertion
	NodeAssertion(
		entry["node_id"],
		node_type(entry["node_type"]),
		read_span(entry["span"]),
		entry["parent"] === nothing ? nothing : entry["parent"],
		Constituent[read_constituent(item) for item in entry["constituents"]],
	)
end

function read_scope(entry)::ScopeAssertion
	ScopeAssertion(entry["assertion_id"], read_span(entry["marker"]), read_span(entry["target"]))
end

read_context(entry)::ContextReference = ContextReference(read_span(entry["span"]), entry["role"])

function read_record(line::AbstractString)::ExaminationRecord
	entry = JSON.parse(line)
	ExaminationRecord(
		entry["record_id"],
		entry["pass"],
		entry["pass_version"],
		entry["population"],
		entry["population_version"],
		read_span(entry["source"]),
		entry["raw_sha256"],
		entry["synthetic_boundary"],
		entry["projection"],
		entry["projection_version"],
		entry["view_sha256"],
		ContextReference[read_context(item) for item in entry["context"]],
		Symbol(entry["outcome"]),
		entry["exhaustive"],
		NodeAssertion[read_assertion(item) for item in entry["assertions"]],
		ScopeAssertion[read_scope(item) for item in entry["scopes"]],
		RawSpan[read_span(item) for item in entry["residuals"]],
		entry["decision_procedure"],
		entry["decision_reference"] === nothing ? nothing : entry["decision_reference"],
		entry["created"],
		entry["notes"],
	)
end

function read_pass(store::Store, pass::AbstractString)::Vector{ExaminationRecord}
	directory = pass_directory(store, pass)
	isdir(directory) || return ExaminationRecord[]
	records = ExaminationRecord[]
	seen_ids = Set{String}()
	seen_targets = Set{Tuple{String, Int, Int}}()
	for path in sort(filter(name -> endswith(name, ".jsonl"), readdir(directory; join = true)))
		shard = first(splitext(basename(path)))
		for (line_number, line) in enumerate(eachline(path))
			isempty(strip(line)) && continue
			record = try
				read_record(line)
			catch failure
				throw(StoreIntegrityError("$(path):$(line_number): cannot read record: $(sprint(showerror, failure))"))
			end
			record.pass == pass || throw(StoreIntegrityError(
				"$(path):$(line_number): record $(record.record_id) declares pass $(record.pass), expected $(pass)",
			))
			shard_of(record) == shard || throw(StoreIntegrityError(
				"$(path):$(line_number): record $(record.record_id) belongs in shard $(shard_of(record))",
			))
			record.record_id in seen_ids && throw(StoreIntegrityError(
				"duplicate record id $(record.record_id) in pass $(pass)",
			))
			push!(seen_ids, record.record_id)
			# The store holds current verdicts, not their history. Two records for one target are a
			# defect in whatever produced them, and there is no precedence rule that could pick
			# between them honestly.
			target = (record.source.file, record.source.start_byte, record.source.end_byte)
			target in seen_targets && throw(StoreIntegrityError(
				"pass $(pass) has more than one record for $(record.source)",
			))
			push!(seen_targets, target)
			push!(records, record)
		end
	end
	sort(records; by = sort_key)
end
