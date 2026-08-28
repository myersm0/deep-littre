struct Store
	root::String
end

struct StoreIntegrityError <: Exception
	detail::String
end

Base.showerror(io::IO, failure::StoreIntegrityError) =
	print(io, "adjudication store integrity failure: ", failure.detail)

pass_directory(store::Store, pass::AbstractString)::String = joinpath(store.root, pass)

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

function write_pass!(store::Store, pass::AbstractString, records::Vector{ExaminationRecord})
	ordered = sort(records; by = sort_key)
	sharded = Dict{String, Vector{ExaminationRecord}}()
	for record in ordered
		record.pass == pass || error("record for pass $(record.pass) written to pass $(pass)")
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

function read_raw_span(entry)::RawSpan
	RawSpan(entry["file"], entry["start_byte"], entry["end_byte"])
end

function read_projected_span(entry)::ProjectedSpan
	ProjectedSpan(entry["start_byte"], entry["end_byte"])
end

function read_constituent(entry)::Constituent
	Constituent(entry["name"], read_projected_span(entry["span"]))
end

function read_assertion(entry)::NodeAssertion
	NodeAssertion(
		entry["node_id"],
		node_type(entry["node_type"]),
		read_projected_span(entry["span"]),
		Constituent[read_constituent(item) for item in entry["constituents"]],
	)
end

function read_scope(entry)::ScopeAssertion
	ScopeAssertion(read_projected_span(entry["marker"]), read_projected_span(entry["target"]))
end

function read_record(line::AbstractString)::ExaminationRecord
	entry = JSON.parse(line)
	ExaminationRecord(
		entry["record_id"],
		entry["pass"],
		entry["pass_version"],
		read_raw_span(entry["source"]),
		entry["surface_sha256"],
		Symbol(entry["outcome"]),
		NodeAssertion[read_assertion(item) for item in entry["assertions"]],
		ScopeAssertion[read_scope(item) for item in entry["scopes"]],
		ProjectedSpan[read_projected_span(item) for item in entry["residuals"]],
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
