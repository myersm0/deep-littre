using ArgParse
using Dates
using TOML
using DeepLittre: Source, Census, Adjudication

const repository_root = normpath(joinpath(@__DIR__, "..", ".."))
const display_width = 88

function settings()
	specification = ArgParseSettings()

	@add_arg_table! specification begin
		"source_dir"
			required = true
		"sample_dir"
			required = true
		"--procedure"
			default = "human/pilot"
		"--patches"
			default = joinpath(repository_root, "patches", "patches.toml")
		"--gold-root"
			default = joinpath(repository_root, "benchmark", "gold", "development")
	end

	return parse_args(specification)
end

struct SampleItem
	item_id::String
	rank::Int
	anchor::Tuple{String, Int, Int}
	surface_sha256::String
end

function sample_items(sample_dir::AbstractString, sample_id::AbstractString)
	lines = readlines(joinpath(sample_dir, "membership.tsv"))
	column = Dict(
		name => index for (index, name) in enumerate(split(popfirst!(lines), '\t'))
	)

	return map(lines) do line
		fields = split(line, '\t')
		rank = parse(Int, fields[column["rank"]])
		return SampleItem(
			"$(sample_id):$(lpad(rank, 4, '0'))",
			rank,
			(
				fields[column["file"]],
				parse(Int, fields[column["start_byte"]]),
				parse(Int, fields[column["end_byte"]]),
			),
			fields[column["surface_sha256"]],
		)
	end
end

shorten(text::AbstractString, width::Int) =
	length(text) <= width ? text : first(text, width) * "…"

function print_wrapped(indent::AbstractString, pieces)
	column = length(indent)
	print(indent)
	for piece in pieces
		if column + length(piece) + 1 > display_width
			print("\n", indent)
			column = length(indent)
		end
		print(piece, " ")
		column += length(piece) + 1
	end
	println()
	return nothing
end

function print_target(target::AbstractString, ranges)
	if isempty(ranges)
		println("  (empty target)")
		return nothing
	end
	println("  ", target)
	println()
	print_wrapped("  ", [
		"$(index):$(SubString(target, range))"
		for (index, range) in enumerate(ranges)
	])
	return nothing
end

function print_item(item, pass, sample_item, position, total, ranges)
	println()
	println("─"^display_width)
	println("[$(position)/$(total)] $(pass.pass)  $(sample_item.item_id)")
	println(
		"  $(item.headword)  ($(join(item.entry_nature, "; ")))  ",
		"$(Census.kind_name(item.block.kind))",
		isnothing(item.rubrique) ? "" : "  [$(item.rubrique)]",
	)
	println()
	print_target(item.projection.text, ranges)
	for marker in item.markers
		typed = isnothing(marker.type) ? marker.element : "$(marker.element)=$(marker.type)"
		println("  marker ($(typed)): $(marker.text)")
	end
	for context in item.context
		println("  $(context.role): ", shorten(context.text, 100))
	end
	println()
	println("  $(pass.question)")
	return nothing
end

token_index(text::AbstractString, ranges) =
	text == "end" ? lastindex(ranges) : parse(Int, text)

function token_range(ranges, input::AbstractString)
	matched = match(r"^(\d+|end)(?:\s*-\s*(\d+|end))?$", input)
	isnothing(matched) && return nothing
	first_index = token_index(matched[1], ranges)
	last_index = isnothing(matched[2]) ? first_index : token_index(matched[2], ranges)
	inside = checkbounds(Bool, ranges, first_index) &&
		checkbounds(Bool, ranges, last_index) &&
		first_index <= last_index
	inside || return nothing
	return first(ranges[first_index]):last(ranges[last_index])
end

const separator_characters = (',', ';', ':')

function trim_separators(target::AbstractString, span)
	stop = last(span)
	while stop >= first(span)
		index = thisind(target, stop)
		character = target[index]
		character in separator_characters || isspace(character) || break
		stop = prevind(target, index)
	end
	return first(span):stop
end

function resolve_range(target::AbstractString, ranges, input::AbstractString)
	span = token_range(ranges, input)
	isnothing(span) || return trim_separators(target, span)
	matches = findall(input, target)
	length(matches) == 1 && return only(matches)
	return nothing
end

function read_range(prompt::AbstractString, target::AbstractString, ranges)
	while true
		print(prompt)
		input = strip(readline())
		isempty(input) && return nothing
		span = resolve_range(target, ranges, input)
		isnothing(span) || return span
		println("  no unique match for $(repr(input))")
	end
end

function read_note()
	print("  note> ")
	return String(strip(readline()))
end

function confirm(prompt::AbstractString)
	print(prompt)
	return startswith(lowercase(strip(readline())), "y")
end

function residual_texts(target::AbstractString, node_ranges)
	pieces = String[]
	position = 1
	for span in sort(node_ranges; by = first)
		push!(pieces, String(strip(SubString(target, position:prevind(target, first(span))))))
		position = nextind(target, last(span))
	end
	push!(pieces, String(strip(SubString(target, position:lastindex(target)))))
	return filter(!isempty, pieces)
end

function author_structure(pass, item)
	target = item.projection.text
	ranges = findall(r"\S+", target)
	selections = Adjudication.FormSelection[]
	node_ranges = UnitRange{Int}[]

	while true
		form = read_range("  form> ", target, ranges)
		isnothing(form) && break
		gloss = read_range("  gloss> ", target, ranges)
		extent = something(gloss, form)
		node = min(first(form), first(extent)):max(last(form), last(extent))
		push!(node_ranges, node)
		push!(selections, Adjudication.FormSelection(
			SubString(target, node),
			SubString(target, form),
			isnothing(gloss) ? nothing : SubString(target, gloss),
		))
		confirm("  another node? [y/N] ") || break
	end

	isempty(selections) && return nothing
	residuals = residual_texts(target, node_ranges)
	isempty(residuals) || println("  residual: ", join(map(repr, residuals), ", "))

	return Adjudication.Decision(
		:positive;
		exhaustive = pass.exhaustive_extraction,
		selections = selections,
		residuals = residuals,
		notes = read_note(),
	)
end

function author_scopes(pass, item)
	target = item.projection.text
	ranges = findall(r"\S+", target)
	scopes = Adjudication.ScopeSelection[]

	while true
		marker = read_range("  marker> ", target, ranges)
		isnothing(marker) && break
		scope_target = read_range("  governs> ", target, ranges)
		isnothing(scope_target) && break
		push!(scopes, Adjudication.ScopeSelection(
			SubString(target, marker), SubString(target, scope_target),
		))
		confirm("  another marker? [y/N] ") || break
	end

	isempty(scopes) && return nothing
	return Adjudication.Decision(:positive; scopes = scopes, notes = read_note())
end

struct Positive end
struct Negative end
struct Unresolved end
struct Skip end
struct Quit end

const commands = Dict{String, Any}(
	"p" => Positive(),
	"n" => Negative(),
	"u" => Unresolved(),
	"s" => Skip(),
	"q" => Quit(),
)

author(::Nothing, pass, item) = author_scopes(pass, item)
author(::Any, pass, item) = author_structure(pass, item)

decide(::Positive, pass, item) = author(pass.node_type, pass, item)
decide(::Negative, pass, item) = Adjudication.Decision(:negative; notes = read_note())
decide(::Unresolved, pass, item) =
	Adjudication.Decision(:unresolved; notes = read_note())
decide(::Skip, pass, item) = nothing

function read_command()
	while true
		print("  [p]ositive [n]egative [u]nresolved [s]kip [q]uit> ")
		input = lowercase(strip(readline()))
		command = get(commands, input, nothing)
		isnothing(command) || return command
	end
end

persist!(store, pass, record) = Adjudication.merge_pass!(store, pass.pass, [record])

function log_item(path, sample_item, outcome, seconds)
	open(path, "a") do io
		println(io, join([
			sample_item.item_id,
			outcome,
			round(seconds; digits = 1),
			Dates.format(Dates.now(Dates.UTC), "yyyy-mm-ddTHH:MM:SSZ"),
		], '\t'))
	end
	return nothing
end

function adjudicate!(harness, pass, store, item, sample_item, procedure)
	command = read_command()
	command isa Quit && return :quit

	decision = decide(command, pass, item)
	isnothing(decision) && return :skipped

	try
		persist!(store, pass, Adjudication.commit!(
			harness, pass, item, decision; decision_procedure = procedure,
		))
	catch failure
		failure isa Adjudication.ReviewItem || rethrow()
		println("  rejected: ", sprint(showerror, failure))
		return :rejected
	end

	return decision.outcome
end

function report_progress(position, total)
	println("  recorded $(position)/$(total)")
	return nothing
end

function main()
	arguments = settings()
	manifest = TOML.parsefile(joinpath(arguments["sample_dir"], "manifest.toml"))
	sample_id = manifest["sample_id"]

	pass = Adjudication.pass_definition(manifest["pass"])
	isnothing(pass) && error("unknown adjudication pass: $(manifest["pass"])")
	pass.pass_version == manifest["pass_version"] ||
		error("sample was drawn under $(pass.pass) v$(manifest["pass_version"])")

	println("loading corpus…")
	documents = Source.read_corpus(
		arguments["source_dir"]; patches_path = arguments["patches"],
	)
	corpus = Census.census(documents)

	gold_dir = joinpath(arguments["gold-root"], sample_id)
	mkpath(gold_dir)
	store = Adjudication.Store(gold_dir)
	harness = Adjudication.Harness(documents, corpus, store)

	items = sample_items(arguments["sample_dir"], sample_id)
	completed = Set(
		Adjudication.anchor_key(record.source)
		for record in Adjudication.read_pass(store, pass.pass)
	)
	session_log = joinpath(gold_dir, "session.tsv")

	println("$(sample_id): $(length(completed)) of $(length(items)) already recorded")

	for sample_item in items
		sample_item.anchor in completed && continue
		block = get(harness.blocks, sample_item.anchor, nothing)
		if isnothing(block)
			println("$(sample_item.item_id): no block at $(sample_item.anchor), skipped")
			continue
		end

		item = Adjudication.adjudication_item(harness, block, sample_item.item_id)
		if Adjudication.surface_sha256(item) != sample_item.surface_sha256
			println("$(sample_item.item_id): surface changed since sampling, skipped")
			continue
		end

		print_item(
			item, pass, sample_item, sample_item.rank, length(items),
			findall(r"\S+", item.projection.text),
		)
		started = time()
		outcome = adjudicate!(
			harness, pass, store, item, sample_item, arguments["procedure"],
		)
		outcome == :quit && break
		outcome == :rejected && continue

		log_item(session_log, sample_item, outcome, time() - started)
		report_progress(sample_item.rank, length(items))
		push!(completed, sample_item.anchor)
	end

	println("\ngold: $(gold_dir)")
	return nothing
end

main()
