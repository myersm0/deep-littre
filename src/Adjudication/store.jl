"""
The authoritative store is text-based and diffable: one canonical JSON object per line, sharded
by pass and source letter. Only this writer serializes committed records.
"""
struct Store
	root::String
end

pass_directory(store::Store, pass::AbstractString)::String = joinpath(store.root, pass)

shard_of(record::ExaminationRecord)::String = first(splitext(record.source.file))

shard_path(store::Store, pass::AbstractString, shard::AbstractString)::String =
	joinpath(pass_directory(store, pass), shard * ".jsonl")

function replace_atomically(path::AbstractString, contents::AbstractString)
	mkpath(dirname(path))
	staging = path * ".staging"
	open(staging, "w") do handle
		write(handle, contents)
	end
	mv(staging, path; force = true)
	nothing
end

"""
	write_pass!(store, pass, records)

Regenerate every shard of one pass. Records are sorted by durable anchor so diffs stay local, and
each shard is replaced atomically.
"""
function write_pass!(store::Store, pass::AbstractString, records::Vector{ExaminationRecord})
	ordered = sort(records; by = sort_key)
	sharded = Dict{String, Vector{ExaminationRecord}}()
	for record in ordered
		record.pass == pass || error("record for pass $(record.pass) written to pass $(pass)")
		push!(get!(sharded, shard_of(record), ExaminationRecord[]), record)
	end
	for (shard, shard_records) in sharded
		buffer = IOBuffer()
		for record in shard_records
			write_json(buffer, record)
			write(buffer, '\n')
		end
		replace_atomically(shard_path(store, pass, shard), String(take!(buffer)))
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

function read_context(entry)::ContextReference
	ContextReference(
		read_span(entry["span"]),
		entry["raw_sha256"],
		entry["projection"],
		entry["projection_version"],
		entry["view_sha256"],
		entry["role"],
	)
end

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
		entry["llm_input_sha256"] === nothing ? nothing : entry["llm_input_sha256"],
		Symbol(entry["outcome"]),
		entry["exhaustive"],
		NodeAssertion[read_assertion(item) for item in entry["assertions"]],
		RawSpan[read_span(item) for item in entry["residuals"]],
		Symbol(entry["method"]),
		entry["adjudicator"],
		entry["model"] === nothing ? nothing : entry["model"],
		entry["created"],
		entry["notes"],
	)
end

function read_pass(store::Store, pass::AbstractString)::Vector{ExaminationRecord}
	directory = pass_directory(store, pass)
	isdir(directory) || return ExaminationRecord[]
	records = ExaminationRecord[]
	for path in sort(filter(name -> endswith(name, ".jsonl"), readdir(directory; join = true)))
		for line in eachline(path)
			isempty(strip(line)) && continue
			push!(records, read_record(line))
		end
	end
	sort(records; by = sort_key)
end
