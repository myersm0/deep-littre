# ── Configuration ────────────────────────────────────────────────

const large_scope_threshold = 15
const calibration_per_bucket = 5
const calibration_seed = 42

# ── Helpers ──────────────────────────────────────────────────────

function all_senses(entry::Entry)
	result = Sense[]
	for el in entry.body
		if el isa Sense
			push!(result, el)
		elseif el isa TransitionGroup
			for sub in el.sub_senses
				sub isa Sense && push!(result, sub)
			end
		end
	end
	result
end

function indent_neighbors(indents::Vector{Indent}, index::Int)::Dict{String, Any}
	result = Dict{String, Any}()
	index > 1 && (result["prev_indent"] = first(strip_tags(indents[index - 1].content), 100))
	index < length(indents) && (result["next_indent"] = first(strip_tags(indents[index + 1].content), 100))
	result
end

# ── Flag collectors ──────────────────────────────────────────────

function flag_unclassified!(flags::Vector{ReviewFlag}, entries::Vector{Entry})
	for entry in entries
		for sense in all_senses(entry)
			for (i, indent) in enumerate(sense.indents)
				cls = indent.classification
				cls === nothing && continue
				cls.role isa Unclassified || continue
				neighbors = indent_neighbors(sense.indents, i)
				push!(flags, ReviewFlag(
					entry_id = entry.id[],
					headword = entry.headword,
					phase = "phase3",
					flag_type = "unclassified",
					reason = "no rule matched",
					context = merge(Dict{String, Any}(
						"sense_num" => sense.num,
						"indent_content" => first(indent.content, 200),
						"method" => string(cls.method),
					), neighbors),
				))
			end
		end
	end
end

function flag_skipped_locutions!(flags::Vector{ReviewFlag}, entries::Vector{Entry})
	for entry in entries
		for sense in all_senses(entry)
			for indent in sense.indents
				role_of(indent) isa Locution || continue
				isempty(indent.canonical_form) || continue
				push!(flags, ReviewFlag(
					entry_id = entry.id[],
					headword = entry.headword,
					phase = "phase4",
					flag_type = "skipped_locution",
					reason = "no canonical form extracted",
					context = Dict{String, Any}(
						"sense_num" => sense.num,
						"indent_content" => first(indent.content, 200),
					),
				))
			end
		end
	end
end

function flag_scope_decisions!(flags::Vector{ReviewFlag}, entries::Vector{Entry})
	for entry in entries
		for el in entry.body
			if el isa TransitionGroup
				num_scoped = length(el.sub_senses)
				flag_type = num_scoped > large_scope_threshold ? "large_scope" : "scope_decision"
				first_content = if !isempty(el.sub_senses) && el.sub_senses[1] isa Sense
					first(strip_tags(el.sub_senses[1].content), 80)
				else
					""
				end
				last_content = if !isempty(el.sub_senses) && el.sub_senses[end] isa Sense
					first(strip_tags(el.sub_senses[end].content), 80)
				else
					""
				end
				push!(flags, ReviewFlag(
					entry_id = entry.id[],
					headword = entry.headword,
					phase = "phase5",
					flag_type = flag_type,
					reason = "$(el.kind) scope, $(num_scoped) senses",
					context = Dict{String, Any}(
						"transition_content" => first(strip_tags(el.transition_content), 100),
						"scope_type" => string(el.kind),
						"transition_form" => el.form,
						"transition_pos" => el.pos,
						"num_scoped" => num_scoped,
						"first_scoped" => first_content,
						"last_scoped" => last_content,
					),
				))

				for sub in el.sub_senses
					sub isa Sense && flag_large_intra!(flags, entry, sub)
				end
			end

			el isa Sense && flag_large_intra!(flags, entry, el)
		end
	end
end

function flag_large_intra!(flags::Vector{ReviewFlag}, entry::Entry, sense::Sense)
	for indent in sense.indents
		r = role_of(indent)
		(r isa NatureLabel || r isa VoiceTransition) || continue
		length(indent.children) > 5 || continue
		push!(flags, ReviewFlag(
			entry_id = entry.id[],
			headword = entry.headword,
			phase = "phase5",
			flag_type = "large_intra_scope",
			reason = "$(typeof(r)) scoped $(length(indent.children)) children",
			context = Dict{String, Any}(
				"sense_num" => sense.num,
				"indent_content" => first(strip_tags(indent.content), 100),
				"num_children" => length(indent.children),
			),
		))
	end
end

function flag_calibration_sample!(flags::Vector{ReviewFlag}, entries::Vector{Entry})
	buckets = Dict{Tuple{String, String}, Vector{Tuple{Entry, Sense, Int, Indent}}}()
	for entry in entries
		for sense in all_senses(entry)
			for (i, indent) in enumerate(sense.indents)
				cls = indent.classification
				cls === nothing && continue
				key = (string(typeof(cls.role)), string(cls.method))
				bucket = get!(buckets, key) do
					Tuple{Entry, Sense, Int, Indent}[]
				end
				push!(bucket, (entry, sense, i, indent))
			end
		end
	end

	rng = MersenneTwister(calibration_seed)
	for (role_method, items) in sort(collect(buckets); by = first)
		role, method = role_method
		sample_size = min(calibration_per_bucket, length(items))
		sample = Random.randperm(rng, length(items))[1:sample_size]
		for idx in sample
			entry, sense, i, indent = items[idx]
			neighbors = indent_neighbors(sense.indents, i)
			push!(flags, ReviewFlag(
				entry_id = entry.id[],
				headword = entry.headword,
				phase = "calibration",
				flag_type = "calibration_sample",
				reason = "sample from $(role)/$(method) (n=$(length(items)))",
				context = merge(Dict{String, Any}(
					"sense_num" => sense.num,
					"indent_content" => first(indent.content, 200),
					"role" => role,
					"method" => method,
					"bucket_size" => length(items),
				), neighbors),
			))
		end
	end
end

const likely_locution_pattern = r"^(Loc\.\s|Locution)"i

function flag_likely_locutions!(flags::Vector{ReviewFlag}, entries::Vector{Entry})
	for entry in entries
		for sense in all_senses(entry)
			for indent in sense.indents
				role_of(indent) isa Locution && continue
				plain = strip_tags(indent.content)
				occursin(likely_locution_pattern, plain) || continue
				push!(flags, ReviewFlag(
					entry_id = entry.id[],
					headword = entry.headword,
					phase = "phase3",
					flag_type = "likely_locution",
					reason = "starts with Loc./Locution but classified as $(typeof(role_of(indent)))",
					context = Dict{String, Any}(
						"sense_num" => sense.num,
						"indent_content" => first(indent.content, 200),
						"current_role" => string(typeof(role_of(indent))),
					),
				))
			end
		end
	end
end

# ── W3 structural flags ──────────────────────────────────────────

function each_nested_indent(f::Function, entry::Entry)
	for sense in all_senses(entry), indent in sense.indents
		_walk_indents(indent, f)
	end
end

function flag_metonymic_glosses!(flags::Vector{ReviewFlag}, entries::Vector{Entry})
	for entry in entries
		each_nested_indent(entry) do indent
			is_metonymic_gloss(indent) || return
			push!(flags, ReviewFlag(
				entry_id = entry.id[],
				headword = entry.headword,
				phase = "structural",
				flag_type = "metonymic_subsense",
				reason = "locution gloss opens with a definite article",
				context = Dict{String, Any}(
					"canonical_form" => indent.canonical_form,
					"gloss" => first(locution_gloss(indent), 200),
				),
			))
		end
	end
end

# A valency shift without a printed transition form cannot become a nested
# homonymicEntry and stays as the sanctioned sense-level <gramGrp> fallback.
function has_valency_reading(text::AbstractString)::Bool
	for target in route_content(text)
		target isa Vector{GramElement} || continue
		any(element -> element.kind == "valency", target) && return true
	end
	false
end

function flag_sense_level_valency!(flags::Vector{ReviewFlag}, entries::Vector{Entry})
	for entry in entries
		for el in entry.body
			el isa TransitionGroup || continue
			el.kind == :medium || continue
			plain = strip_tags(el.transition_content)
			has_valency_reading(plain) || continue
			push!(flags, ReviewFlag(
				entry_id = entry.id[],
				headword = entry.headword,
				phase = "structural",
				flag_type = "sense_level_valency",
				reason = "valency transition scoped without a printed form",
				context = Dict{String, Any}(
					"transition_content" => first(plain, 100),
					"num_scoped" => length(el.sub_senses),
				),
			))
		end
	end
end

function flag_synonyme_citations!(flags::Vector{ReviewFlag}, entries::Vector{Entry})
	for entry in entries
		rubriques = vcat(entry.rubriques,
			Rubrique[r for sense in all_senses(entry) for r in sense.rubriques])
		for rub in rubriques
			rub.kind isa Synonyme || continue
			n = length(rub.citations) + sum(length(i.citations) for i in rub.indents; init = 0)
			n > 0 || continue
			push!(flags, ReviewFlag(
				entry_id = entry.id[],
				headword = entry.headword,
				phase = "structural",
				flag_type = "synonyme_citations",
				reason = "$(n) citations emitted as siblings after the synonymy xr",
				context = Dict{String, Any}("num_citations" => n),
			))
		end
	end
end

# Handoff count for the classification branch: intra-sense transitions carrying
# a printed form (reflexive or locution pre-text) that remain sense-level
# pending the scope decision on whether the form governs beyond its own sense.
function flag_intra_sense_forms!(flags::Vector{ReviewFlag}, entries::Vector{Entry})
	for entry in entries
		each_nested_indent(entry) do indent
			is_transition(indent) || return
			gs = split_gram(markup_to_tei(indent.content))
			gs.pre_kind in (:reflexive_form, :locution_form) || return
			push!(flags, ReviewFlag(
				entry_id = entry.id[],
				headword = entry.headword,
				phase = "structural",
				flag_type = "intra_sense_form",
				reason = "printed form on an intra-sense transition ($(gs.pre_kind))",
				context = Dict{String, Any}(
					"form" => gs.pre_text,
					"label" => gs.label_text,
				),
			))
		end
	end
end

# ── Entry point ──────────────────────────────────────────────────

function etymology_rubriques(entry::Entry)::Vector{Rubrique}
	rubriques = Rubrique[rubrique for rubrique in entry.rubriques if rubrique.kind isa Etymologie]
	for sense in all_senses(entry)
		append!(rubriques,
			Rubrique[rubrique for rubrique in sense.rubriques if rubrique.kind isa Etymologie])
	end
	rubriques
end

function flag_suspect_etym_tokens!(flags::Vector{ReviewFlag}, entries::Vector{Entry})
	resolved_cues = 0
	suspects = 0
	fallbacks = 0
	for entry in entries
		for rubrique in etymology_rubriques(entry)
			contents = vcat([rubrique.content],
				String[indent.content for indent in rubrique.indents])
			for content in contents
				isempty(strip(content)) && continue
				segments = segment_etymology(content)
				if length(segments) == 1 && segments[1] isa EtymProse && occursin('<', content)
					fallbacks += 1
					push!(flags, ReviewFlag(
						entry_id = entry.id[],
						headword = entry.headword,
						phase = "etymology",
						flag_type = "etym_fallback",
						reason = "content carries markup outside the segmentable inventory; emitted as pre-W4 prose",
						context = Dict{String, Any}(
							"content" => first(content, 160),
						),
					))
				end
				for segment in segments
					if segment isa EtymSuspect
						suspects += 1
						push!(flags, ReviewFlag(
							entry_id = entry.id[],
							headword = entry.headword,
							phase = "etymology",
							flag_type = "suspect_language_token",
							reason = "token in language-abbreviation position missing from language table",
							context = Dict{String, Any}(
								"token" => segment.token,
								"anchor" => segment.anchor,
							),
						))
					elseif segment isa EtymCit
						segment.cue === nothing || (resolved_cues += 1)
						segment.defaulted && push!(flags, ReviewFlag(
							entry_id = entry.id[],
							headword = entry.headword,
							phase = "etymology",
							flag_type = "cognate_defaulted",
							reason = "etymon-vs-cognate not disambiguated by surrounding prose",
							context = Dict{String, Any}(
								"forms" => join(segment.forms, ", "),
							),
						))
					end
				end
			end
		end
	end
	total = resolved_cues + suspects
	rate = total == 0 ? 100.0 : round(100 * resolved_cues / total; digits = 1)
	@info "etym language cues: $(resolved_cues) resolved, $(suspects) suspect ($(rate)% hit rate), $(fallbacks) fallback rubriques"
end

function collect_flags(entries::Vector{Entry})::Vector{ReviewFlag}
	flags = ReviewFlag[]
	flag_unclassified!(flags, entries)
	flag_skipped_locutions!(flags, entries)
	flag_likely_locutions!(flags, entries)
	flag_scope_decisions!(flags, entries)
	flag_metonymic_glosses!(flags, entries)
	flag_sense_level_valency!(flags, entries)
	flag_synonyme_citations!(flags, entries)
	flag_intra_sense_forms!(flags, entries)
	flag_suspect_etym_tokens!(flags, entries)
	flag_calibration_sample!(flags, entries)

	by_type = Dict{String, Int}()
	for f in flags
		by_type[f.flag_type] = get(by_type, f.flag_type, 0) + 1
	end
	@info "$(length(flags)) flags total"
	for (ft, count) in sort(collect(by_type); by = last, rev = true)
		@info "  $(rpad(ft, 25)) $(count)"
	end

	flags
end
