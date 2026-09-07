struct Store
	root::String
end

struct StoreIntegrityError <: Exception
	detail::String
end

Base.showerror(io::IO, failure::StoreIntegrityError) =
	print(io, "adjudication store integrity failure: ", failure.detail)

integrity_error(detail::AbstractString) = throw(StoreIntegrityError(detail))

integrity_error(record::ExaminationRecord, reason::AbstractString) =
	integrity_error("record $(record.record_id) $(reason)")

pass_directory(store::Store, pass::AbstractString)::String = joinpath(store.root, pass)

shard_of(record::ExaminationRecord)::String = first(splitext(record.source.file))

shard_path(store::Store, pass::AbstractString, shard::AbstractString)::String =
	joinpath(pass_directory(store, pass), shard * ".jsonl")

locator(record::ExaminationRecord) =
	(record.source.file, record.source.start_byte, record.source.end_byte)

function holds_records(store::Store, name::AbstractString)::Bool
	directory = joinpath(store.root, name)
	isdir(directory) || return false
	return any(endswith(entry, ".jsonl") for entry in readdir(directory))
end

function store_pass_directories(store::Store)::Vector{String}
	isdir(store.root) || return String[]
	return sort([name for name in readdir(store.root) if holds_records(store, name)])
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
	return nothing
end

function shard_records(pass::AbstractString, records::Vector{ExaminationRecord})
	sharded = Dict{String, Vector{ExaminationRecord}}()
	for record in sort(records; by = sort_key)
		record.pass == pass || error("record for pass $(record.pass) written to pass $(pass)")
		push!(get!(sharded, shard_of(record), ExaminationRecord[]), record)
	end
	return sharded
end

function write_shard(staging::AbstractString, shard::AbstractString, records)
	buffer = IOBuffer()
	for record in records
		write_json(buffer, record)
		write(buffer, '\n')
	end
	return open(joinpath(staging, shard * ".jsonl"), "w") do handle
		write(handle, String(take!(buffer)))
	end
end

function write_pass!(
	store::Store, pass::AbstractString, records::Vector{ExaminationRecord},
)
	sharded = shard_records(pass, records)
	mkpath(store.root)
	directory = pass_directory(store, pass)
	staging = directory * ".staging." * string(uuid4())
	mkpath(staging)
	try
		for (shard, records) in sharded
			write_shard(staging, shard, records)
		end
		replace_directory!(directory, staging)
	catch
		ispath(staging) && rm(staging; recursive = true, force = true)
		rethrow()
	end
	return sharded
end

read_raw_span(entry)::RawSpan =
	RawSpan(entry["file"], entry["start_byte"], entry["end_byte"])

read_projected_span(entry)::ProjectedSpan =
	ProjectedSpan(entry["start_byte"], entry["end_byte"])

read_constituent(entry)::Constituent = Constituent(
	entry["name"], read_projected_span(entry["span"]), get(entry, "value", nothing),
)

read_assertion(entry)::NodeAssertion = NodeAssertion(
	entry["node_id"],
	node_type(entry["node_type"]),
	read_projected_span(entry["span"]),
	Constituent[read_constituent(item) for item in entry["constituents"]],
)

read_scope(entry)::ScopeAssertion = ScopeAssertion(
	read_projected_span(entry["marker"]), read_projected_span(entry["target"]),
)

function read_record(line::AbstractString)::ExaminationRecord
	entry = JSON.parse(line)
	return ExaminationRecord(
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
		entry["decision_reference"],
		entry["created"],
		entry["notes"],
	)
end

function read_shard(
	path::AbstractString,
	pass::AbstractString,
	records::Vector{ExaminationRecord},
	seen_ids::Set{String},
	seen_targets::Set{Tuple{String, Int, Int}},
)
	shard = first(splitext(basename(path)))
	for (line_number, line) in enumerate(eachline(path))
		isempty(strip(line)) && continue
		location = "$(path):$(line_number)"
		record = try
			read_record(line)
		catch failure
			integrity_error("$(location): cannot read record: $(sprint(showerror, failure))")
		end
		record.pass == pass || integrity_error(
			"$(location): record $(record.record_id) declares pass " *
			"$(record.pass), expected $(pass)",
		)
		shard_of(record) == shard || integrity_error(
			"$(location): record $(record.record_id) belongs in shard $(shard_of(record))",
		)
		isempty(strip(record.decision_procedure)) && integrity_error(
			"$(location): record $(record.record_id) names no decision procedure",
		)
		record.record_id in seen_ids &&
			integrity_error("duplicate record id $(record.record_id) in pass $(pass)")
		push!(seen_ids, record.record_id)
		locator(record) in seen_targets &&
			integrity_error("pass $(pass) has more than one record for $(record.source)")
		push!(seen_targets, locator(record))
		push!(records, record)
	end
	return records
end

function read_pass(store::Store, pass::AbstractString)::Vector{ExaminationRecord}
	directory = pass_directory(store, pass)
	isdir(directory) || return ExaminationRecord[]
	records = ExaminationRecord[]
	seen_ids = Set{String}()
	seen_targets = Set{Tuple{String, Int, Int}}()
	paths = filter(name -> endswith(name, ".jsonl"), readdir(directory; join = true))
	for path in sort(paths)
		read_shard(path, pass, records, seen_ids, seen_targets)
	end
	return sort(records; by = sort_key)
end

"""
Add records to a pass without rewriting the verdicts already in it. A record whose
locator is already held is refused; superseding a verdict must be intentional, by
regenerating the pass with `write_pass!`.
"""
function merge_pass!(
	store::Store, pass::AbstractString, records::Vector{ExaminationRecord},
)
	existing = read_pass(store, pass)
	held = Set(locator(record) for record in existing)
	incoming = Set{Tuple{String, Int, Int}}()
	for record in records
		key = locator(record)
		key in held &&
			integrity_error("pass $(pass) already holds a record for $(record.source)")
		key in incoming &&
			integrity_error("merge batch has more than one record for $(record.source)")
		push!(incoming, key)
	end
	write_pass!(store, pass, vcat(existing, records))
	return nothing
end
