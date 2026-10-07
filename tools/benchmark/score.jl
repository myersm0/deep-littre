using ArgParse
using JSON
using TOML
using DeepLittre: Adjudication

const repository_root = normpath(joinpath(@__DIR__, "..", ".."))

include("annotation.jl")

function settings()
	specification = ArgParseSettings()

	@add_arg_table! specification begin
		"sample_dir"
			required = true
		"run_dir"
			required = true
		"--gold"
			help = "gold pass directory or .jsonl file; default " *
				"benchmark/gold/<role>/<sample_id>/<pass>"
			default = nothing
		"--listing"
			help = "items to write to the run's listing: disagreements, all, or none"
			default = "disagreements"
	end

	return parse_args(specification)
end

# ===== inputs =====

struct Member
	item_id::String
	rank::Int
	headword::String
	kind::String
	file::String
	surface_sha256::String
end

function read_members(sample_dir::AbstractString)::Vector{Member}
	lines = readlines(joinpath(sample_dir, "membership.tsv"))
	column = Dict(
		name => index for (index, name) in enumerate(split(popfirst!(lines), '\t'))
	)
	return map(lines) do line
		fields = split(line, '\t')
		return Member(
			fields[column["item_id"]],
			parse(Int, fields[column["rank"]]),
			fields[column["headword"]],
			fields[column["kind"]],
			fields[column["file"]],
			fields[column["surface_sha256"]],
		)
	end
end

function read_targets(sample_dir::AbstractString)::Dict{String, String}
	targets = Dict{String, String}()
	for line in eachline(joinpath(sample_dir, "surfaces.jsonl"))
		isempty(strip(line)) && continue
		surface = JSON.parse(line)
		targets[surface["item_id"]] = surface["target"]
	end
	return targets
end

record_files(path::AbstractString) = isdir(path) ?
	sort(filter(name -> endswith(name, ".jsonl"), readdir(path; join = true))) :
	[path]

const RecordKey = Tuple{String, String}

record_key(record::Adjudication.ExaminationRecord)::RecordKey =
	(record.source.file, record.surface_sha256)

record_key(member::Member)::RecordKey = (member.file, member.surface_sha256)

function read_records(path::AbstractString)
	records = Dict{RecordKey, Adjudication.ExaminationRecord}()
	ispath(path) || return records
	for file in record_files(path), line in eachline(file)
		isempty(strip(line)) && continue
		record = Adjudication.read_record(line)
		haskey(records, record_key(record)) &&
			error("$(path) holds more than one record for $(record.source)")
		records[record_key(record)] = record
	end
	return records
end

function read_responses(run_dir::AbstractString)::Dict{String, Any}
	path = joinpath(run_dir, "responses.jsonl")
	responses = Dict{String, Any}()
	isfile(path) || return responses
	for line in eachline(path)
		isempty(strip(line)) && continue
		response = JSON.parse(line)
		responses[response["item_id"]] = response
	end
	return responses
end

# ===== what the method did with each item =====

struct Decided
	record::Adjudication.ExaminationRecord
end

struct Abstained
	record::Adjudication.ExaminationRecord
end

struct AuthoringFailure
	status::String
	detail::String
	content::String
end

struct NotRun
	status::String
end

const Prediction = Union{Decided, Abstained, AuthoringFailure, NotRun}

const not_run_statuses = (
	"missing_block", "surface_changed", "ineligible", "transport_error",
)

function prediction(member::Member, records, responses)::Prediction
	record = get(records, record_key(member), nothing)
	if !isnothing(record)
		record.outcome == :unresolved && return Abstained(record)
		return Decided(record)
	end
	response = get(responses, member.item_id, nothing)
	isnothing(response) && return NotRun("not run")
	response["status"] in not_run_statuses && return NotRun(response["status"])
	return AuthoringFailure(
		response["status"],
		something(get(response, "detail", ""), ""),
		something(get(response, "content", ""), ""),
	)
end

label(prediction::Decided) = String(prediction.record.outcome)
label(::Abstained) = "abstained"
label(::AuthoringFailure) = "authoring failure"
label(::NotRun) = "not run"

# ===== comparing semantic output =====

struct Exact end
struct Tolerant end

const trailing_separators = ('.', ',', ';', ':', '!', '?')

span_key(span, target, ::Exact) = (span.start_byte, span.end_byte)

function span_key(span, target, ::Tolerant)
	stop = prevind(target, span.end_byte)
	while stop > span.start_byte &&
			(target[stop] in trailing_separators || isspace(target[stop]))
		stop = prevind(target, stop)
	end
	return (span.start_byte, nextind(target, stop))
end

function constituent_keys(assertion, name, target, mode)
	return sort([
		span_key(part.span, target, mode)
		for part in assertion.constituents if part.name == name
	])
end

node_key(assertion, target, mode) = (
	constituent_keys(assertion, "form", target, mode),
	constituent_keys(assertion, "gloss", target, mode),
)

node_keys(record, target, mode) =
	Set(node_key(assertion, target, mode) for assertion in record.assertions)

form_keys(record, target, mode) = Set(
	key for assertion in record.assertions
	for key in constituent_keys(assertion, "form", target, mode)
)

gloss_keys(record, target, mode) = Set(
	key for assertion in record.assertions
	for key in constituent_keys(assertion, "gloss", target, mode)
)

same_output(gold, predicted, target, mode) =
	gold.outcome == predicted.outcome &&
	node_keys(gold, target, mode) == node_keys(predicted, target, mode)

# ===== tallies =====

mutable struct Overlap
	gold::Int
	predicted::Int
	matched::Int
end

Overlap() = Overlap(0, 0, 0)

function add!(overlap::Overlap, gold::Set, predicted::Set)
	overlap.gold += length(gold)
	overlap.predicted += length(predicted)
	overlap.matched += length(intersect(gold, predicted))
	return overlap
end

mutable struct Tally
	members::Int
	gold_missing::Int
	gold_unresolved::Int
	not_run::Int
	scored::Int
	gold_positive::Int
	decided::Int
	abstained::Int
	authoring_failures::Int
	true_positive::Int
	false_positive::Int
	false_negative::Int
	true_negative::Int
	exact_output::Int
	tolerant_output::Int
	exact_nodes::Overlap
	tolerant_nodes::Overlap
	exact_forms::Overlap
	tolerant_forms::Overlap
	exact_glosses::Overlap
	tolerant_glosses::Overlap
	failure_statuses::Dict{String, Int}
end

Tally() = Tally(
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	Overlap(), Overlap(), Overlap(), Overlap(), Overlap(), Overlap(),
	Dict{String, Int}(),
)

struct Comparison
	member::Member
	target::String
	gold::Union{Nothing, Adjudication.ExaminationRecord}
	prediction::Prediction
	scored::Bool
	exact::Bool
	tolerant::Bool
end

disagrees(comparison::Comparison) = comparison.scored && !comparison.exact

tally_prediction!(tally, gold, prediction::NotRun, target) = (tally.not_run += 1)

function tally_prediction!(tally, gold, prediction::AuthoringFailure, target)
	tally.scored += 1
	tally.authoring_failures += 1
	tally.failure_statuses[prediction.status] =
		get(tally.failure_statuses, prediction.status, 0) + 1
	return nothing
end

function tally_prediction!(tally, gold, prediction::Abstained, target)
	tally.scored += 1
	tally.abstained += 1
	return nothing
end

function tally_prediction!(tally, gold, prediction::Decided, target)
	tally.scored += 1
	tally.decided += 1
	predicted = prediction.record
	gold_positive = gold.outcome == :positive
	predicted_positive = predicted.outcome == :positive
	tally.true_positive += gold_positive && predicted_positive
	tally.false_positive += !gold_positive && predicted_positive
	tally.false_negative += gold_positive && !predicted_positive
	tally.true_negative += !gold_positive && !predicted_positive
	tally.exact_output += same_output(gold, predicted, target, Exact())
	tally.tolerant_output += same_output(gold, predicted, target, Tolerant())
	if gold_positive && predicted_positive
		add_overlaps!(
			gold, predicted, target, Exact(),
			tally.exact_nodes, tally.exact_forms, tally.exact_glosses,
		)
		add_overlaps!(
			gold, predicted, target, Tolerant(),
			tally.tolerant_nodes, tally.tolerant_forms, tally.tolerant_glosses,
		)
	end
	return nothing
end

function add_overlaps!(gold, predicted, target, mode, nodes, forms, glosses)
	add!(nodes, node_keys(gold, target, mode), node_keys(predicted, target, mode))
	add!(forms, form_keys(gold, target, mode), form_keys(predicted, target, mode))
	add!(glosses, gloss_keys(gold, target, mode), gloss_keys(predicted, target, mode))
	return nothing
end

function compare!(tally::Tally, member, target, gold, prediction)::Comparison
	tally.members += 1
	if isnothing(gold)
		tally.gold_missing += 1
		return Comparison(member, target, gold, prediction, false, false, false)
	end
	if gold.outcome == :unresolved
		tally.gold_unresolved += 1
		return Comparison(member, target, gold, prediction, false, false, false)
	end
	scored = !(prediction isa NotRun)
	scored && (tally.gold_positive += gold.outcome == :positive)
	tally_prediction!(tally, gold, prediction, target)
	decided = prediction isa Decided
	exact = decided && same_output(gold, prediction.record, target, Exact())
	tolerant = decided && same_output(gold, prediction.record, target, Tolerant())
	return Comparison(member, target, gold, prediction, scored, exact, tolerant)
end

# ===== reporting =====

ratio(numerator, denominator) = denominator == 0 ? nothing : numerator / denominator

function shown(numerator, denominator)::String
	value = ratio(numerator, denominator)
	isnothing(value) && return "–"
	return "$(round(value; digits = 3))  ($(numerator)/$(denominator))"
end

precision_of(overlap::Overlap) = (overlap.matched, overlap.predicted)
recall_of(overlap::Overlap) = (overlap.matched, overlap.gold)

function summary_lines(tally::Tally)::Vector{Pair{String, String}}
	predicted_positive = tally.true_positive + tally.false_positive
	return [
		"items" => string(tally.members),
		"no gold record" => string(tally.gold_missing),
		"gold unresolved (not scored)" => string(tally.gold_unresolved),
		"not run" => string(tally.not_run),
		"scored" => string(tally.scored),
		"" => "",
		"decided" => shown(tally.decided, tally.scored),
		"abstained" => shown(tally.abstained, tally.scored),
		"authoring failures" => shown(tally.authoring_failures, tally.scored),
		"" => "",
		"positive precision" => shown(tally.true_positive, predicted_positive),
		"positive recall" => shown(tally.true_positive, tally.gold_positive),
		"outcome accuracy, decided" =>
			shown(tally.true_positive + tally.true_negative, tally.decided),
		"exact output, decided" => shown(tally.exact_output, tally.decided),
		"tolerant output, decided" => shown(tally.tolerant_output, tally.decided),
		"" => "",
		"node precision, exact" => shown(precision_of(tally.exact_nodes)...),
		"node recall, exact" => shown(recall_of(tally.exact_nodes)...),
		"node precision, tolerant" => shown(precision_of(tally.tolerant_nodes)...),
		"node recall, tolerant" => shown(recall_of(tally.tolerant_nodes)...),
		"form precision, tolerant" => shown(precision_of(tally.tolerant_forms)...),
		"form recall, tolerant" => shown(recall_of(tally.tolerant_forms)...),
		"gloss precision, tolerant" => shown(precision_of(tally.tolerant_glosses)...),
		"gloss recall, tolerant" => shown(recall_of(tally.tolerant_glosses)...),
	]
end

function print_summary(io::IO, tally::Tally)
	for (name, value) in summary_lines(tally)
		isempty(name) ? println(io) : println(io, "  ", rpad(name, 30), value)
	end
	if !isempty(tally.failure_statuses)
		println(io, "\n  authoring failures by kind")
		by_frequency = sort(collect(tally.failure_statuses); by = last, rev = true)
		for (status, count) in by_frequency
			println(io, "    ", rpad(status, 28), count)
		end
	end
	return nothing
end

overlap_table(overlap::Overlap) = Dict(
	"gold" => overlap.gold,
	"predicted" => overlap.predicted,
	"matched" => overlap.matched,
)

function score_table(tally::Tally, header)::Dict{String, Any}
	counts = Dict(
		string(name) => getfield(tally, name)
		for name in fieldnames(Tally) if getfield(tally, name) isa Int
	)
	overlaps = Dict(
		string(name) => overlap_table(getfield(tally, name))
		for name in fieldnames(Tally) if getfield(tally, name) isa Overlap
	)
	return Dict(
		"run" => header,
		"counts" => counts,
		"overlaps" => overlaps,
		"failure_statuses" => tally.failure_statuses,
	)
end

function describe(io::IO, record::Adjudication.ExaminationRecord, target)
	println(io, record.outcome)
	isempty(record.assertions) || print_wrapped(io, "      ", annotated(target, record))
	isempty(record.notes) || println(io, "      note: ", record.notes)
	return nothing
end

describe(io::IO, prediction::Union{Decided, Abstained}, target) =
	describe(io, prediction.record, target)
describe(io::IO, prediction::NotRun, target) =
	println(io, "not run (", prediction.status, ")")

function describe(io::IO, prediction::AuthoringFailure, target)
	println(io, prediction.status, ": ", prediction.detail)
	isempty(prediction.content) || print_wrapped(io, "      ", prediction.content)
	return nothing
end

describe(io::IO, ::Nothing, target) = println(io, "no gold record")

function verdict(comparison::Comparison)::String
	comparison.scored || return "not scored"
	comparison.exact && return "agree"
	comparison.tolerant && return "differ only in trailing punctuation"
	return "disagree"
end

function write_comparison(io::IO, comparison::Comparison)
	member = comparison.member
	println(io, "─"^display_width)
	println(io, "[$(member.rank)] $(member.item_id)  $(member.headword)  $(member.kind)")
	println(io, "  ", verdict(comparison))
	print_wrapped(io, "  ", comparison.target)
	print(io, "  gold        ")
	describe(io, comparison.gold, comparison.target)
	print(io, "  predicted   ")
	describe(io, comparison.prediction, comparison.target)
	return nothing
end

struct Disagreements end
struct Everything end
struct NoListing end

const listings = Dict(
	"disagreements" => Disagreements(), "all" => Everything(), "none" => NoListing(),
)

listed(::Disagreements, comparison) = disagrees(comparison)
listed(::Everything, comparison) = true
listed(::NoListing, comparison) = false

function main()
	arguments = settings()
	sample_dir = arguments["sample_dir"]
	run_dir = arguments["run_dir"]
	listing = get(listings, arguments["listing"], nothing)
	isnothing(listing) &&
		error("--listing must be one of $(join(sort(collect(keys(listings))), ", "))")

	manifest = TOML.parsefile(joinpath(sample_dir, "manifest.toml"))
	gold_path = something(
		arguments["gold"],
		joinpath(
			repository_root, "benchmark", "gold",
			manifest["role"], manifest["sample_id"], manifest["pass"],
		),
	)
	ispath(gold_path) || error("no gold at $(gold_path)")
	header = TOML.parsefile(joinpath(run_dir, "run.toml"))
	header["sample_id"] == manifest["sample_id"] ||
		error("$(run_dir) is a run over $(header["sample_id"]), not $(manifest["sample_id"])")

	targets = read_targets(sample_dir)
	gold = read_records(gold_path)
	predicted = read_records(joinpath(run_dir, "records.jsonl"))
	responses = read_responses(run_dir)

	tally = Tally()
	comparisons = [
		compare!(
			tally, member, targets[member.item_id],
			get(gold, record_key(member), nothing),
			prediction(member, predicted, responses),
		)
		for member in read_members(sample_dir)
	]

	listing_path = joinpath(run_dir, "listing.txt")
	open(listing_path, "w") do io
		for comparison in comparisons
			listed(listing, comparison) && write_comparison(io, comparison)
		end
	end
	open(joinpath(run_dir, "score.toml"), "w") do io
		TOML.print(io, score_table(tally, header); sorted = true)
	end

	println("$(header["sample_id"])  $(header["decision_procedure"])")
	println("gold: $(gold_path)\n")
	print_summary(stdout, tally)
	println("\nlisting: $(listing_path)")
	return nothing
end

main()
