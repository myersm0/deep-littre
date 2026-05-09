#!/usr/bin/env julia
#
# Voice transition scope judgment via Ollama.
# Reads candidates CSV, runs per-label yes/no judgments with short-circuit
# logic, writes results to JSONL.
#
# Usage:
#	julia scripts/judge_scope.jl candidates.csv --model qwen2.5:72b
#	julia scripts/judge_scope.jl candidates.csv --model qwen2.5:72b --all
#	julia scripts/judge_scope.jl candidates.csv --model qwen2.5:72b --all \
#		--exclude judge_scope_qwen2.5_72b.jsonl

using ArgParse
using CSV
using HTTP
using JSON3
using Tables

include("glossary.jl")
using .Glossary: match_entries

const ollama_url = "http://localhost:11434/api/chat"

const system_prompt = """
Vous traitez des étiquettes grammaticales d'un dictionnaire français du XIXe siècle (Littré).

Votre tâche : répondre par « oui » ou « non » à des questions d'applicabilité.

Répondez par un seul mot : « oui » ou « non ». Aucune explication, aucune ponctuation supplémentaire.
"""

function parse_arguments()
	settings = ArgParseSettings()
	@add_arg_table! settings begin
		"candidates_path"
			default = "data/classification/scope_candidates.csv"
		"--model"
			default = "qwen2.5:72b"
		"--limit"
			arg_type = Int
			default = 100
		"--all"
			action = :store_true
		"--output"
			default = nothing
		"--exclude"
			default = nothing
	end
	ArgParse.parse_args(settings)
end

label_key(row) = (row.label_file, row.label_line)

function load_candidates(path)
	rows = CSV.File(path) |> Tables.rowtable
	rows
end

function group_by_label(rows)
	groups = Vector{Vector{eltype(rows)}}()
	current = eltype(rows)[]
	current_key = nothing
	for row in rows
		row_key = label_key(row)
		if row_key != current_key
			isempty(current) || push!(groups, current)
			current = eltype(rows)[]
			current_key = row_key
		end
		push!(current, row)
	end
	isempty(current) || push!(groups, current)
	groups
end

function load_exclude_keys(path)
	keys = Set{Tuple{String, Int, String, Int, String}}()
	for line in eachline(path)
		isempty(strip(line)) && continue
		record = JSON3.read(line)
		push!(keys, (
			String(record[:label_file]),
			Int(record[:label_line]),
			String(record[:target_file]),
			Int(record[:target_line]),
			String(record[:target_kind]),
		))
	end
	keys
end

function build_glosses_block(label_text)
	matches = match_entries(label_text)
	isempty(matches) && return ""
	lines = ["- *$(entry.label)* : $(entry.gloss)" for entry in matches]
	"Dans le *Dictionnaire* de Littré :\n" * join(lines, "\n") * "\n\n"
end

function build_self_prompt(headword, label_text)
	glosses = build_glosses_block(label_text)
	"""
	$(glosses)Mot-vedette : **$(headword)**

	L'indent suivant porte l'étiquette grammaticale : *$(label_text)*

	> $(label_text)

	L'indent fournit-il, de lui-même, au moins un exemple complet de l'emploi annoncé par l'étiquette ?
	"""
end

function build_target_prompt(headword, label_text, target_text)
	glosses = build_glosses_block(label_text)
	"""
	$(glosses)Mot-vedette : **$(headword)**

	Étiquette grammaticale : *$(label_text)*

	Le passage suivant illustre-t-il un emploi du mot-vedette conforme à cette étiquette ?

	> $(target_text)
	"""
end

function query_ollama(model, user_prompt)
	body = JSON3.write(Dict(
		"model" => model,
		"messages" => [
			Dict("role" => "system", "content" => system_prompt),
			Dict("role" => "user", "content" => user_prompt),
		],
		"stream" => false,
		"options" => Dict("num_predict" => 10, "temperature" => 0.0),
	))
	response = HTTP.post(ollama_url, ["Content-Type" => "application/json"], body)
	data = JSON3.read(response.body)
	strip(String(data.message.content))
end

function parse_yes_no(raw)
	text = lowercase(strip(raw))
	occursin(r"\boui\b", text) && return "oui"
	occursin(r"\bnon\b", text) && return "non"
	nothing
end

function make_record(row, answer, status, raw)
	Dict(
		"label_file" => row.label_file,
		"label_line" => row.label_line,
		"label_text" => row.label_text,
		"target_file" => row.target_file,
		"target_line" => row.target_line,
		"target_kind" => row.target_kind,
		"headword" => row.headword,
		"entry_id" => row.entry_id,
		"answer" => answer,
		"status" => status,
		"raw" => raw,
	)
end

function process_label_group(group, model, out, counter)
	consecutive_non = 0

	for row in group
		if row.target_kind == "self"
			prompt = build_self_prompt(row.headword, row.label_text)
		elseif isempty(row.target_text)
			record = make_record(row, "", "missing_target", "")
			println(out, JSON3.write(record))
			flush(out)
			counter[] += 1
			continue
		else
			prompt = build_target_prompt(row.headword, row.label_text, row.target_text)
		end

		record = try
			raw = query_ollama(model, prompt)
			answer = parse_yes_no(raw)
			if answer === nothing
				make_record(row, "", "parse_error", raw)
			else
				make_record(row, answer, "ok", raw)
			end
		catch exc
			make_record(row, "", "error:$exc", "")
		end

		println(out, JSON3.write(record))
		flush(out)
		counter[] += 1

		status_str = record["status"]
		answer_str = record["answer"]
		println("[$(counter[])] $(rpad(row.entry_id, 20)) $(rpad(row.target_kind, 10)) $(rpad(answer_str, 4)) $status_str")

		if row.target_kind == "self" && answer_str == "oui"
			return
		end

		if row.target_kind != "self"
			if answer_str == "non"
				consecutive_non += 1
				consecutive_non >= 2 && return
			else
				consecutive_non = 0
			end
		end
	end
end

function main()
	args = parse_arguments()

	model = args["model"]
	model_tag = replace(replace(model, ":" => "_"), "/" => "_")
	output_path = something(args["output"], "judge_scope_$(model_tag).jsonl")
	limit = args["all"] ? nothing : args["limit"]

	exclude_keys = if !isnothing(args["exclude"])
		keys = load_exclude_keys(args["exclude"])
		println("Excluding $(length(keys)) items from $(args["exclude"])")
		keys
	else
		Set{Tuple{String, Int, String, Int, String}}()
	end

	println("Loading candidates from $(args["candidates_path"])...")
	rows = load_candidates(args["candidates_path"])

	if !isempty(exclude_keys)
		filter!(r -> (r.label_file, r.label_line, r.target_file, r.target_line, r.target_kind) ∉ exclude_keys, rows)
	end

	groups = group_by_label(rows)
	if !isnothing(limit)
		groups = groups[1:min(limit, length(groups))]
	end

	total_rows = sum(length(g) for g in groups)
	println("Got $(length(groups)) label groups ($(total_rows) candidate rows)")
	println("Model: $model")
	println("Output: $output_path\n")

	counter = Ref(0)
	open(output_path, "a") do out
		for group in groups
			process_label_group(group, model, out, counter)
		end
	end

	println("\nWrote $(counter[]) judgments to $output_path")
end

main()
