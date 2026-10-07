using ArgParse
using Dates
using Downloads
using JSON
using SHA
using TOML
using DeepLittre: Source, Census, Adjudication
using DeepLittre.Adjudication: ProjectedSpan

const repository_root = normpath(joinpath(@__DIR__, "..", ".."))

function settings()
	specification = ArgParseSettings()

	@add_arg_table! specification begin
		"source_dir"
			required = true
		"sample_dir"
			required = true
		"prompt"
			help = "prompt file (TOML)"
			required = true
		"--model"
			required = true
		"--output"
			help = "run directory; default <sample_dir>/predictions/<prompt>__<model>"
			default = nothing
		"--endpoint"
			default = "http://localhost:11434/api/chat"
		"--temperature"
			arg_type = Float64
			default = 0.0
		"--seed"
			arg_type = Int
			default = 0
		"--context-length"
			help = "Ollama num_ctx"
			arg_type = Int
			default = 8192
		"--max-answer-tokens"
			help = "Ollama num_predict"
			arg_type = Int
			default = 1024
		"--timeout"
			help = "seconds to wait for one answer, including loading the model"
			arg_type = Float64
			default = 1800.0
		"--think"
			help = "on, off, or model-default; off skips a thinking model's reasoning"
			default = "model-default"
		"--limit"
			help = "stop after this many items; 0 runs them all"
			arg_type = Int
			default = 0
		"--patches"
			default = joinpath(repository_root, "patches", "patches.toml")
	end

	return parse_args(specification)
end

# ===== prompt =====

const placeholders = (
	"headword", "entry_nature", "rubrique", "kind", "target", "markers", "context",
)

struct Prompt
	path::String
	name::String
	system::String
	user::String
	examples::Vector{Dict{String, Any}}
	sha256::String
end

function read_prompt(path::AbstractString)::Prompt
	parsed = TOML.parsefile(path)
	for field in ("name", "system", "user")
		haskey(parsed, field) || error("$(path): prompt has no $(repr(field))")
	end
	examples = Dict{String, Any}[example for example in get(parsed, "example", [])]
	for (index, example) in enumerate(examples)
		haskey(example, "answer") || error("$(path): example $(index) has no answer")
		try
			parse_answer(example["answer"])
		catch failure
			failure isa UnusableAnswer || rethrow()
			error("$(path): example $(index) answer is unusable: $(failure.reason)")
		end
		fill_template(parsed["user"], template_values(example))
	end
	return Prompt(
		path,
		parsed["name"],
		parsed["system"],
		parsed["user"],
		examples,
		bytes2hex(sha256(read(path))),
	)
end

function fill_template(template::AbstractString, values::Dict{String, String})::String
	return replace(template, r"\{\{(\w+)\}\}" => function (placeholder)
		name = match(r"\{\{(\w+)\}\}", placeholder)[1]
		haskey(values, name) ||
			error("unknown placeholder {{$(name)}}; known: $(join(placeholders, ", "))")
		return values[name]
	end)
end

marker_label(marker) =
	isnothing(marker.type) ? marker.element : "$(marker.element)=$(marker.type)"

function template_values(item::Adjudication.AdjudicationItem)::Dict{String, String}
	return Dict(
		"headword" => item.headword,
		"entry_nature" => join(item.entry_nature, "; "),
		"rubrique" => something(item.rubrique, ""),
		"kind" => Census.kind_name(item.block.kind),
		"target" => item.projection.text,
		"markers" => join(
			("$(marker_label(marker)): $(marker.text)" for marker in item.markers),
			"\n",
		),
		"context" => join(
			("$(context.role): $(context.text)" for context in item.context), "\n",
		),
	)
end

template_values(example::Dict{String, Any})::Dict{String, String} =
	Dict(name => string(get(example, name, "")) for name in placeholders)

user_message(prompt::Prompt, source) =
	fill_template(prompt.user, template_values(source))

message(role::AbstractString, content::AbstractString) =
	Dict("role" => role, "content" => content)

function conversation(prompt::Prompt, item::Adjudication.AdjudicationItem)
	messages = [message("system", prompt.system)]
	for example in prompt.examples
		push!(messages, message("user", user_message(prompt, example)))
		push!(messages, message("assistant", strip(example["answer"])))
	end
	push!(messages, message("user", user_message(prompt, item)))
	return messages
end

# ===== the model's answer =====

const answer_schema = Dict(
	"type" => "object",
	"properties" => Dict(
		"outcome" => Dict(
			"type" => "string", "enum" => ["positive", "negative", "unresolved"],
		),
		"nodes" => Dict(
			"type" => "array",
			"items" => Dict(
				"type" => "object",
				"properties" => Dict(
					"forms" => Dict(
						"type" => "array", "items" => Dict("type" => "string"),
					),
					"gloss" => Dict("type" => "string"),
				),
				"required" => ["forms", "gloss"],
			),
		),
	),
	"required" => ["outcome", "nodes"],
)

struct UnusableAnswer <: Exception
	reason::String
end

struct ProposedNode
	forms::Vector{String}
	gloss::String
end

struct Positive end
struct Negative end
struct Unresolved end

const outcome_kinds = Dict(
	"positive" => Positive(), "negative" => Negative(), "unresolved" => Unresolved(),
)

struct ProposedAnswer
	outcome::Union{Positive, Negative, Unresolved}
	nodes::Vector{ProposedNode}
end

function parse_answer(content::AbstractString)::ProposedAnswer
	parsed = try
		JSON.parse(content)
	catch
		throw(UnusableAnswer("not JSON"))
	end
	parsed isa AbstractDict || throw(UnusableAnswer("not a JSON object"))
	outcome = get(outcome_kinds, get(parsed, "outcome", nothing), nothing)
	isnothing(outcome) && throw(UnusableAnswer("no recognized outcome"))
	nodes = get(parsed, "nodes", [])
	nodes isa AbstractVector || throw(UnusableAnswer("nodes is not a list"))
	return ProposedAnswer(outcome, [proposed_node(node) for node in nodes])
end

function proposed_node(node)::ProposedNode
	node isa AbstractDict || throw(UnusableAnswer("a node is not a JSON object"))
	forms = get(node, "forms", nothing)
	forms isa AbstractVector && all(form -> form isa AbstractString, forms) ||
		throw(UnusableAnswer("a node's forms are not a list of strings"))
	gloss = something(get(node, "gloss", ""), "")
	gloss isa AbstractString || throw(UnusableAnswer("a node's gloss is not a string"))
	return ProposedNode(String.(forms), String(strip(gloss)))
end

# ===== locating the answer in the target =====

struct UnlocatedText <: Exception
	label::String
	text::String
end

struct FoldedText
	text::String
	origins::Dict{Int, Int}
end

fold(character::Char) = character in ('’', '‘') ? '\'' : lowercase(character)

function folded(text::AbstractString)::FoldedText
	buffer = IOBuffer()
	origins = Dict{Int, Int}()
	for index in eachindex(text)
		isspace(text[index]) && continue
		origins[position(buffer) + 1] = index
		print(buffer, fold(text[index]))
	end
	return FoldedText(String(take!(buffer)), origins)
end

function occurrences(target::AbstractString, fragment::AbstractString)
	exact = findall(fragment, target)
	isempty(exact) || return exact
	folded_target = folded(target)
	folded_fragment = folded(fragment).text
	isempty(folded_fragment) && return UnitRange{Int}[]
	return [
		folded_target.origins[first(found)]:folded_target.origins[last(found)]
		for found in findall(folded_fragment, folded_target.text)
	]
end

function token_extent(target::AbstractString, found::UnitRange{Int})::UnitRange{Int}
	start = first(found)
	while start > 1 && !isspace(target[prevind(target, start)])
		start = prevind(target, start)
	end
	stop = last(found)
	while nextind(target, stop) <= ncodeunits(target) &&
			!isspace(target[nextind(target, stop)])
		stop = nextind(target, stop)
	end
	while stop > start && (target[stop] in (',', ';', ':') || isspace(target[stop]))
		stop = prevind(target, stop)
	end
	return start:stop
end

projected(target::AbstractString, found::UnitRange{Int}) =
	ProjectedSpan(first(found), nextind(target, last(found)))

function locate(
	target::AbstractString,
	fragment::AbstractString,
	label::AbstractString,
	cursor::Int,
)::ProjectedSpan
	candidates = occurrences(target, strip(fragment))
	isempty(candidates) && throw(UnlocatedText(label, fragment))
	after_cursor = findfirst(found -> first(found) >= cursor, candidates)
	chosen = candidates[something(after_cursor, 1)]
	return projected(target, token_extent(target, chosen))
end

struct LocatedNode
	span::ProjectedSpan
	forms::Vector{ProjectedSpan}
	gloss::Union{Nothing, ProjectedSpan}
end

function located_nodes(target::AbstractString, nodes::Vector{ProposedNode})
	cursor = 1
	located = LocatedNode[]
	for node in nodes
		forms = ProjectedSpan[]
		for form in node.forms
			span = locate(target, form, "form", cursor)
			push!(forms, span)
			cursor = span.end_byte
		end
		gloss = nothing
		if !isempty(node.gloss)
			gloss = locate(target, node.gloss, "gloss", cursor)
			cursor = gloss.end_byte
		end
		parts = isnothing(gloss) ? forms : vcat(forms, gloss)
		isempty(parts) && continue
		span = ProjectedSpan(
			minimum(part -> part.start_byte, parts),
			maximum(part -> part.end_byte, parts),
		)
		in_source_order = sort(forms; by = form -> form.start_byte)
		push!(located, LocatedNode(span, in_source_order, gloss))
	end
	return located
end

function trimmed(
	target::AbstractString, start::Int, stop::Int,
)::Union{Nothing, ProjectedSpan}
	while start < stop && isspace(target[start])
		start = nextind(target, start)
	end
	while stop > start && isspace(target[prevind(target, stop)])
		stop = prevind(target, stop)
	end
	stop > start || return nothing
	return ProjectedSpan(start, stop)
end

function residual_spans(
	target::AbstractString, nodes::Vector{LocatedNode},
)::Vector{ProjectedSpan}
	residuals = ProjectedSpan[]
	position = 1
	for node in sort(nodes; by = node -> node.span.start_byte)
		gap = trimmed(target, position, node.span.start_byte)
		isnothing(gap) || push!(residuals, gap)
		position = max(position, node.span.end_byte)
	end
	gap = trimmed(target, position, ncodeunits(target) + 1)
	isnothing(gap) || push!(residuals, gap)
	return residuals
end

decision(::Negative, answer, target) = Adjudication.Decision(:negative)
decision(::Unresolved, answer, target) = Adjudication.Decision(:unresolved)

function decision(::Positive, answer::ProposedAnswer, target::AbstractString)
	nodes = located_nodes(target, answer.nodes)
	return Adjudication.Decision(
		:positive;
		exhaustive = true,
		selections = [
			Adjudication.FormSelection(node.span, node.forms, node.gloss)
			for node in nodes
		],
		residuals = residual_spans(target, nodes),
	)
end

# ===== talking to Ollama =====

const think_settings = Dict("model-default" => nothing, "on" => true, "off" => false)

function think_setting(name::AbstractString)
	haskey(think_settings, name) ||
		error("--think must be one of $(join(sort(collect(keys(think_settings))), ", "))")
	return think_settings[name]
end

function patient_downloader()::Downloads.Downloader
	downloader = Downloads.Downloader()
	downloader.easy_hook = (easy, info) ->
		Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_LOW_SPEED_TIME, 0)
	return downloader
end

const downloader = patient_downloader()

struct ModelReply
	content::String
	prompt_tokens::Int
	answer_tokens::Int
end

function request_body(arguments, messages)::String
	body = Dict{String, Any}(
		"model" => arguments["model"],
		"messages" => messages,
		"stream" => false,
		"format" => answer_schema,
		"options" => Dict(
			"temperature" => arguments["temperature"],
			"seed" => arguments["seed"],
			"num_ctx" => arguments["context-length"],
			"num_predict" => arguments["max-answer-tokens"],
		),
	)
	think = think_setting(arguments["think"])
	isnothing(think) || (body["think"] = think)
	return JSON.json(body)
end

function ask_model(arguments, messages)::ModelReply
	output = IOBuffer()
	Downloads.request(
		arguments["endpoint"];
		method = "POST",
		headers = ["Content-Type" => "application/json"],
		input = IOBuffer(request_body(arguments, messages)),
		output = output,
		timeout = arguments["timeout"],
		downloader = downloader,
	)
	reply = JSON.parse(String(take!(output)))
	haskey(reply, "error") && error("ollama: $(reply["error"])")
	return ModelReply(
		reply["message"]["content"],
		get(reply, "prompt_eval_count", 0),
		get(reply, "eval_count", 0),
	)
end

# ===== the run =====

struct SampleItem
	item_id::String
	rank::Int
	anchor::Tuple{String, Int, Int}
	surface_sha256::String
end

function sample_items(sample_dir::AbstractString)::Vector{SampleItem}
	lines = readlines(joinpath(sample_dir, "membership.tsv"))
	column = Dict(
		name => index for (index, name) in enumerate(split(popfirst!(lines), '\t'))
	)
	return map(lines) do line
		fields = split(line, '\t')
		return SampleItem(
			fields[column["item_id"]],
			parse(Int, fields[column["rank"]]),
			(
				fields[column["file"]],
				parse(Int, fields[column["start_byte"]]),
				parse(Int, fields[column["end_byte"]]),
			),
			fields[column["surface_sha256"]],
		)
	end
end

function git_value(command)
	try
		return cd(repository_root) do
			String(strip(read(pipeline(command; stderr = devnull), String)))
		end
	catch
		return "unknown"
	end
end

model_tag(model::AbstractString) = replace(model, r"[^A-Za-z0-9._-]" => "_")

prompt_tag(prompt::Prompt) = replace(prompt.name, r"[^A-Za-z0-9._@-]" => "_")

function run_header(arguments, manifest, prompt::Prompt)::Dict{String, Any}
	return Dict(
		"sample_id" => manifest["sample_id"],
		"pass" => manifest["pass"],
		"pass_version" => manifest["pass_version"],
		"model" => arguments["model"],
		"endpoint" => arguments["endpoint"],
		"temperature" => arguments["temperature"],
		"seed" => arguments["seed"],
		"context_length" => arguments["context-length"],
		"max_answer_tokens" => arguments["max-answer-tokens"],
		"think" => arguments["think"],
		"prompt_name" => prompt.name,
		"prompt_path" => relpath(abspath(prompt.path), repository_root),
		"prompt_sha256" => prompt.sha256,
		"decision_procedure" => decision_procedure(arguments, prompt),
	)
end

decision_procedure(arguments, prompt::Prompt) =
	"ollama/$(arguments["model"])/$(prompt.name)"

function open_run!(run_dir::AbstractString, header::Dict{String, Any})
	mkpath(run_dir)
	path = joinpath(run_dir, "run.toml")
	if isfile(path)
		existing = TOML.parsefile(path)
		changed = [
			key for key in keys(header) if get(existing, key, nothing) != header[key]
		]
		isempty(changed) || error(
			"$(run_dir) was started with different settings ($(join(changed, ", "))); " *
			"use another --output",
		)
		return nothing
	end
	open(path, "w") do io
		TOML.print(io, merge(header, Dict(
			"started_utc" => string(now(UTC)),
			"repository_commit" => git_value(`git rev-parse HEAD`),
			"repository_dirty" => !isempty(git_value(`git status --porcelain`)),
			"julia_version" => string(VERSION),
		)); sorted = true)
	end
	return nothing
end

const not_attempted = ("transport_error",)

function finished_items(run_dir::AbstractString)::Set{String}
	path = joinpath(run_dir, "responses.jsonl")
	isfile(path) || return Set{String}()
	finished = Set{String}()
	for line in eachline(path)
		isempty(strip(line)) && continue
		response = JSON.parse(line)
		response["status"] in not_attempted && continue
		push!(finished, response["item_id"])
	end
	return finished
end

function append_line(path::AbstractString, line::AbstractString)
	open(path, "a") do io
		println(io, line)
	end
	return nothing
end

function record_line(record::Adjudication.ExaminationRecord)::String
	buffer = IOBuffer()
	Adjudication.write_json(buffer, record)
	return String(take!(buffer))
end

struct Attempt
	status::String
	detail::String
	record::Union{Nothing, Adjudication.ExaminationRecord}
	reply::Union{Nothing, ModelReply}
end

function attempt(arguments, prompt, harness, pass, item)::Attempt
	reply = try
		ask_model(arguments, conversation(prompt, item))
	catch failure
		failure isa InterruptException && rethrow()
		return Attempt("transport_error", sprint(showerror, failure), nothing, nothing)
	end
	try
		answer = parse_answer(reply.content)
		record = Adjudication.commit!(
			harness, pass, item, decision(answer.outcome, answer, item.projection.text);
			decision_procedure = decision_procedure(arguments, prompt),
		)
		return Attempt("committed", "", record, reply)
	catch failure
		failure isa UnusableAnswer &&
			return Attempt("unusable_answer", failure.reason, nothing, reply)
		failure isa UnlocatedText && return Attempt(
			"unlocated_text", "$(failure.label) $(repr(failure.text))", nothing, reply,
		)
		failure isa Adjudication.ReviewItem &&
			return Attempt(failure.category, failure.detail, nothing, reply)
		rethrow()
	end
end

outcome_name(::Nothing) = nothing
outcome_name(record::Adjudication.ExaminationRecord) = String(record.outcome)

function response_line(sample_item::SampleItem, attempt::Attempt, seconds::Float64)
	reply = attempt.reply
	return JSON.json(Dict(
		"item_id" => sample_item.item_id,
		"rank" => sample_item.rank,
		"surface_sha256" => sample_item.surface_sha256,
		"status" => attempt.status,
		"outcome" => outcome_name(attempt.record),
		"detail" => attempt.detail,
		"seconds" => round(seconds; digits = 2),
		"prompt_tokens" => isnothing(reply) ? 0 : reply.prompt_tokens,
		"answer_tokens" => isnothing(reply) ? 0 : reply.answer_tokens,
		"content" => isnothing(reply) ? nothing : reply.content,
	))
end

function skipped_line(sample_item::SampleItem, status::AbstractString)
	return JSON.json(Dict(
		"item_id" => sample_item.item_id,
		"rank" => sample_item.rank,
		"surface_sha256" => sample_item.surface_sha256,
		"status" => status,
	))
end

function report_progress(sample_item, total, attempt, seconds, done, remaining, started)
	elapsed_minutes = (time() - started) / 60
	rate = done / max(elapsed_minutes, 1e-9)
	label = something(outcome_name(attempt.record), attempt.status)
	println(
		"[$(sample_item.rank)/$(total)] $(sample_item.item_id)  $(rpad(label, 22))",
		"$(lpad(round(seconds; digits = 1), 6)) s  ",
		"$(round(rate; digits = 1)) items/min  ",
		"eta $(round(Int, remaining / rate)) min",
	)
	isempty(attempt.detail) || println("    ", first(attempt.detail, 160))
	return nothing
end

eligible(harness, pass, block) = Adjudication.population_predicate(pass.population)(
	block.kind, get(harness.rubriques, block.source_id, nothing),
)

function main()
	arguments = settings()
	sample_dir = arguments["sample_dir"]
	manifest = TOML.parsefile(joinpath(sample_dir, "manifest.toml"))
	pass = Adjudication.pass_definition(manifest["pass"])
	isnothing(pass) && error("unknown adjudication pass: $(manifest["pass"])")
	pass.pass_version == manifest["pass_version"] ||
		error("sample was drawn under $(pass.pass) v$(manifest["pass_version"])")

	think_setting(arguments["think"])
	prompt = read_prompt(arguments["prompt"])
	run_dir = something(
		arguments["output"],
		joinpath(
			sample_dir, "predictions",
			"$(prompt_tag(prompt))__$(model_tag(arguments["model"]))",
		),
	)
	open_run!(run_dir, run_header(arguments, manifest, prompt))
	records_path = joinpath(run_dir, "records.jsonl")
	responses_path = joinpath(run_dir, "responses.jsonl")

	println("loading corpus…")
	documents = Source.read_corpus(
		arguments["source_dir"]; patches_path = arguments["patches"],
	)
	corpus = Census.census(documents)
	harness = Adjudication.Harness(documents, corpus, Adjudication.Store(mktempdir()))

	items = sample_items(sample_dir)
	finished = finished_items(run_dir)
	pending = filter(sample_item -> !(sample_item.item_id in finished), items)
	arguments["limit"] > 0 && (pending = first(pending, arguments["limit"]))
	println("$(manifest["sample_id"]): $(length(finished)) of $(length(items)) done, ",
		"running $(length(pending))")
	println("model $(arguments["model"]), prompt $(prompt.name)")
	println("run: $(run_dir)\n")

	started = time()
	for (done, sample_item) in enumerate(pending)
		block = get(harness.blocks, sample_item.anchor, nothing)
		if isnothing(block)
			println("[$(sample_item.rank)] $(sample_item.item_id): no block at anchor")
			append_line(responses_path, skipped_line(sample_item, "missing_block"))
			continue
		end
		if !eligible(harness, pass, block)
			println("[$(sample_item.rank)] $(sample_item.item_id): outside the population")
			append_line(responses_path, skipped_line(sample_item, "ineligible"))
			continue
		end
		item = Adjudication.adjudication_item(harness, block, sample_item.item_id)
		if Adjudication.surface_sha256(item) != sample_item.surface_sha256
			println("[$(sample_item.rank)] $(sample_item.item_id): surface changed")
			append_line(responses_path, skipped_line(sample_item, "surface_changed"))
			continue
		end

		item_started = time()
		result = attempt(arguments, prompt, harness, pass, item)
		seconds = time() - item_started

		if result.status in not_attempted
			println("stopping at $(sample_item.item_id): $(result.detail)")
			break
		end
		if !isnothing(result.record)
			append_line(records_path, record_line(result.record))
		end
		append_line(responses_path, response_line(sample_item, result, seconds))
		report_progress(
			sample_item, length(items), result, seconds,
			done, length(pending) - done, started,
		)
	end

	println("\nrun: $(run_dir)")
	return nothing
end

main()
