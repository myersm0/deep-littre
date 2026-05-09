using DeepLittre: Entry, Sense, Indent, BodyElement, Classification, NatureLabel, VoiceTransition, SourceLocation, strip_tags, is_transition_content, parse_all, enrich!

const target_horizon = 30

struct Candidate
	label_file::String
	label_line::Int
	label_text::String
	target_file::String
	target_line::Int
	target_kind::String
	target_text::String
	headword::String
	entry_id::String
end

is_transition(role) = role isa NatureLabel || role isa VoiceTransition

function transition_role(indent::Indent)
	indent.classification === nothing && return nothing
	is_transition(indent.classification.role) ? indent.classification.role : nothing
end

function extract_label_text(indent::Indent)::String
	strip_tags(indent.content)
end

source_or_zero(source::Union{Nothing, SourceLocation}) =
	source === nothing ? ("", 0) : (source.file, source.line)

function emit_candidate!(candidates, label_source, label_text, target_file, target_line, target_kind, target_text, entry)
	label_file, label_line = source_or_zero(label_source)
	push!(candidates, Candidate(
		label_file,
		label_line,
		label_text,
		target_file,
		target_line,
		target_kind,
		target_text,
		entry.headword,
		entry.id[],
	))
end

function collect_senses(entry::Entry)::Vector{Sense}
	[body_element for body_element in entry.body if body_element isa Sense]
end

function extract_for_sense!(candidates, sense::Sense, sense_index::Int, all_senses::Vector{Sense}, entry::Entry)
	indents = sense.indents
	isempty(indents) && return

	for (indent_index, indent) in enumerate(indents)
		role = transition_role(indent)
		role === nothing && continue

		label_text = extract_label_text(indent)
		isempty(label_text) && continue

		emit_candidate!(candidates, indent.source, label_text,
			source_or_zero(indent.source)..., "self", label_text, entry)

		if indent_index == length(indents)
			horizon_end = min(sense_index + target_horizon, length(all_senses))
			for following_index in (sense_index + 1):horizon_end
				following_sense = all_senses[following_index]
				target_file, target_line = source_or_zero(following_sense.source)
				target_text = strip_tags(following_sense.content)
				emit_candidate!(candidates, indent.source, label_text,
					target_file, target_line, "variante", target_text, entry)
			end
		else
			horizon_end = min(indent_index + target_horizon, length(indents))
			for following_index in (indent_index + 1):horizon_end
				following_indent = indents[following_index]
				following_role = transition_role(following_indent)
				following_role === nothing || break
				target_file, target_line = source_or_zero(following_indent.source)
				target_text = strip_tags(following_indent.content)
				emit_candidate!(candidates, indent.source, label_text,
					target_file, target_line, "indent", target_text, entry)
			end
		end
	end
end

function extract_for_variante_level!(candidates, sense::Sense, sense_index::Int, all_senses::Vector{Sense}, entry::Entry)
	is_transition_content(sense.content) || return
	label_text = strip_tags(sense.content)
	isempty(label_text) && return

	self_file, self_line = source_or_zero(sense.source)
	emit_candidate!(candidates, sense.source, label_text,
		self_file, self_line, "self", label_text, entry)

	horizon_end = min(sense_index + target_horizon, length(all_senses))
	for following_index in (sense_index + 1):horizon_end
		following_sense = all_senses[following_index]
		target_file, target_line = source_or_zero(following_sense.source)
		target_text = strip_tags(following_sense.content)
		emit_candidate!(candidates, sense.source, label_text,
			target_file, target_line, "variante", target_text, entry)
	end
end

function extract_from_entry(entry::Entry)::Vector{Candidate}
	candidates = Candidate[]
	all_senses = collect_senses(entry)
	for (sense_index, sense) in enumerate(all_senses)
		extract_for_variante_level!(candidates, sense, sense_index, all_senses, entry)
		extract_for_sense!(candidates, sense, sense_index, all_senses, entry)
	end
	candidates
end

function extract_all(entries::Vector{Entry})::Vector{Candidate}
	candidates = Candidate[]
	for entry in entries
		append!(candidates, extract_from_entry(entry))
	end
	candidates
end

function csv_escape(value::String)::String
	needs_quoting = any(c -> c in (',', '"', '\n'), value)
	needs_quoting || return value
	'"' * replace(value, '"' => "\"\"") * '"'
end

function write_csv(path::String, candidates::Vector{Candidate})
	open(path, "w") do io
		println(io, "label_file,label_line,label_text,target_file,target_line,target_kind,target_text,headword,entry_id")
		for candidate in candidates
			println(io, join([
				candidate.label_file,
				candidate.label_line,
				csv_escape(candidate.label_text),
				candidate.target_file,
				candidate.target_line,
				candidate.target_kind,
				csv_escape(candidate.target_text),
				csv_escape(candidate.headword),
				candidate.entry_id,
			], ","))
		end
	end
end

if abspath(PROGRAM_FILE) == @__FILE__
	length(ARGS) >= 2 || error("Usage: julia $(@__FILE__) <source_dir> <output_csv> [patches_path] [verdicts_path]")
	source_dir = ARGS[1]
	output_csv = ARGS[2]
	patches_path = length(ARGS) >= 3 ? ARGS[3] : nothing
	verdicts_path = length(ARGS) >= 4 ? ARGS[4] : nothing

	entries = parse_all(source_dir; patches_path)
	enrich!(entries; verdicts_path)
	candidates = extract_all(entries)
	write_csv(output_csv, candidates)
	@info "Wrote $(length(candidates)) candidates to $output_csv"
end
