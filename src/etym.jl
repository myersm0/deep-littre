# ── Etymology segmentation (W4) ──────────────────────────────────
# The single tokenizer over Gannaz-layer Etymologie content. Both consumers —
# flag_suspect_etym_tokens! (review flags) and the TEI emitter's <cit>
# construction — call this on the same string, so the suspect residue in the
# output matches the side-channel report by construction. Position-detection
# logic exists exactly once, here; the emitter serializes verdicts and never
# re-locates language-abbreviation positions in post-substitution text.

struct EtymLanguageTable
	languages::Dict{String, Tuple{String, String}}
	skip::Set{String}
end

function load_etym_language_table(
		path::AbstractString = joinpath(data_directory, "etym_language_table.toml"))::EtymLanguageTable
	parsed = TOML.parsefile(path)
	EtymLanguageTable(
		Dict{String, Tuple{String, String}}(
			key => (value["code"], get(value, "expand", ""))
			for (key, value) in parsed["language"]
		),
		Set{String}(parsed["non_language"]["skip"]),
	)
end

const etym_language_table = load_etym_language_table()

# ── Segment vocabulary ───────────────────────────────────────────

struct EtymCue
	printed::String
	expand::String
	code::String
end

struct EtymCit
	cit_type::Symbol
	language::String
	cue::Union{Nothing, EtymCue}
	fictif::Bool
	forms::Vector{String}
	gloss::String
	defaulted::Bool
end

struct EtymConnector
	printed::String
end

struct EtymCrossReference
	label::String
	target::String
	printed::String
end

struct EtymProse
	markup::String
end

struct EtymSuspect
	token::String
	anchor::String
end

const EtymSegment = Union{EtymCit, EtymConnector, EtymCrossReference, EtymProse, EtymSuspect}

with_gloss(cit::EtymCit, gloss::AbstractString)::EtymCit =
	EtymCit(cit.cit_type, cit.language, cit.cue, cit.fictif, cit.forms, String(gloss), cit.defaulted)

# ── Token vocabulary ─────────────────────────────────────────────

const etym_connector_words =
	Set(["et", "ou", "du", "de", "des", "dérivé", "dérivée", "tiré", "tirée"])
const etym_label_modifiers = Set(["radical", "racine"])
const etym_derivational_pattern = r"\b(?:du|des)\b|\bdériv|\btiré|^de\b"
const etym_reference_label_tail = r"((?:[Vv]oy(?:ez)?|[Cc]f|[Cc]omparez)\.?)\s*$"
const etym_greek_pattern = r"[\p{Greek}][\p{Greek}\p{M}']*"
const etym_punctuation_characters = [' ', ',', ';', '.', '(', ')', ':']

normalize_etym_token(token::AbstractString)::String =
	lowercase(strip(token, [',', ';', '(', ')', ':', ' ']))

is_punctuation_token(token::AbstractString)::Bool =
	isempty(strip(token, etym_punctuation_characters))

clean_prose_span(span::AbstractString)::String =
	String(rstrip(lstrip(strip(span), [',', ';', '(', ')', ' ']), [',', ';', '(', ' ']))

# ── Event extraction ─────────────────────────────────────────────
# Events are the anchors of the walk: wrapped forms (Gannaz <i>, with or
# without a lang attribute), bare Greek-script runs, and <a ref> links. Text
# between events carries cues, connectors, glosses, prose, and suspects.

struct EtymEvent
	kind::Symbol
	range::UnitRange{Int}
	forms::Vector{String}
	language::String
	target::String
	printed::String
end

function etym_events(content::String)::Vector{EtymEvent}
	events = EtymEvent[]
	spans = UnitRange{Int}[]
	for matched in eachmatch(r"<i\b([^>]*)>(.*?)</i>"s, content)
		language_match = match(r"lang=\"([^\"]+)\"", matched.captures[1])
		language = language_match === nothing ? "" : String(language_match.captures[1])
		forms = String[strip(form) for form in split(matched.captures[2], ',')]
		filter!(!isempty, forms)
		range = matched.offset:(matched.offset + ncodeunits(matched.match) - 1)
		push!(spans, range)
		isempty(forms) && continue
		push!(events, EtymEvent(:form, range, forms, language, "", ""))
	end
	for matched in eachmatch(r"<a ref=\"([^\"]*)\">(.*?)</a>"s, content)
		range = matched.offset:(matched.offset + ncodeunits(matched.match) - 1)
		push!(spans, range)
		push!(events, EtymEvent(:anchor, range, String[], "",
			String(matched.captures[1]), strip_tags(String(matched.captures[2]))))
	end
	for matched in eachmatch(etym_greek_pattern, content)
		any(matched.offset in span for span in spans) && continue
		range = matched.offset:(matched.offset + ncodeunits(matched.match) - 1)
		push!(events, EtymEvent(:form, range, String[String(matched.match)], "grc", "", ""))
	end
	sort!(events; by = event -> first(event.range))
end

# ── Pending state between a gap and the event it governs ─────────

mutable struct EtymPending
	cues::Vector{EtymCue}
	connectors::Vector{String}
	fictif::Bool
	derivational::Bool
	prose_seen::Bool
	language_hint::String
	xr_label::String
end

EtymPending() = EtymPending(EtymCue[], String[], false, false, false, "", "")

function reset_pending!(pending::EtymPending)
	empty!(pending.cues)
	empty!(pending.connectors)
	pending.fictif = false
	pending.derivational = false
	pending.prose_seen = false
	pending.language_hint = ""
	pending.xr_label = ""
end

cit_type_of(pending::EtymPending)::Symbol = pending.derivational ? :etymon : :cognate

is_defaulted(pending::EtymPending)::Bool = !pending.derivational && pending.prose_seen

# ── Cue matching ─────────────────────────────────────────────────
# Longest multi-token key wins; label-modifier words (radical, racine) extend
# the printed label leftward without touching expand/norm resolution.

function match_cue_at(tokens::Vector{<:AbstractString}, start::Int,
		table::EtymLanguageTable)::Tuple{Union{Nothing, EtymCue}, Int, String}
	total = length(tokens)
	key_start = start
	while key_start <= total && normalize_etym_token(tokens[key_start]) in etym_label_modifiers
		key_start += 1
	end
	for key_length in reverse(1:min(3, total - key_start + 1))
		candidate = normalize_etym_token(join(tokens[key_start:key_start + key_length - 1], ' '))
		haskey(table.languages, candidate) || continue
		printed = strip(join(tokens[start:key_start + key_length - 1], ' '), [',', ' '])
		code, expand = table.languages[candidate]
		return EtymCue(String(printed), expand, code), key_start + key_length - start, candidate
	end
	nothing, 0, ""
end

function full_name_language_hint(tokens::Vector{<:AbstractString},
		table::EtymLanguageTable)::String
	total = length(tokens)
	for key_length in reverse(1:min(3, total))
		candidate = normalize_etym_token(join(tokens[total - key_length + 1:total], ' '))
		occursin('.', candidate) && continue
		haskey(table.languages, candidate) && return table.languages[candidate][1]
	end
	""
end

# ── Cluster grammar ──────────────────────────────────────────────
# cue (et cue)* fictif? bare_form* trailing? — where cues joined by et share
# the following form and split into separate cits with the connector between.

struct EtymCluster
	cues::Vector{EtymCue}
	connectors::Vector{String}
	fictif::Bool
	forms::Vector{String}
	trailing::Vector{String}
end

function parse_cue_cluster(tokens::Vector{<:AbstractString},
		table::EtymLanguageTable)::Union{Nothing, EtymCluster}
	cues = EtymCue[]
	connectors = String[]
	position = 1
	total = length(tokens)
	while true
		cue, consumed, _ = match_cue_at(tokens, position, table)
		if cue === nothing
			isempty(cues) && return nothing
			break
		end
		push!(cues, cue)
		position += consumed
		position <= total || break
		connector = normalize_etym_token(tokens[position])
		connector in ("et", "ou") || break
		following, _, _ = match_cue_at(tokens, position + 1, table)
		following === nothing && break
		push!(connectors, String(strip(tokens[position], [',', ' '])))
		position += 1
	end
	fictif = position <= total && normalize_etym_token(tokens[position]) == "fictif"
	fictif && (position += 1)
	forms = String[]
	while position <= total
		token = tokens[position]
		stripped = strip(token, [' '])
		push!(forms, String(rstrip(stripped, [',', '.'])))
		position += 1
		endswith(stripped, ',') && break
	end
	EtymCluster(cues, connectors, fictif, forms, String[tokens[position:total]...])
end

# ── Gap processing ───────────────────────────────────────────────

function push_prose!(segments::Vector{EtymSegment}, text::AbstractString)
	cleaned = clean_prose_span(text)
	isempty(cleaned) || push!(segments, EtymProse(cleaned))
end

function gloss_qualifies(text::AbstractString, table::EtymLanguageTable)::Bool
	occursin('<', text) && return false
	words = split(text)
	isempty(words) && return false
	for word in words
		normalized = normalize_etym_token(word)
		normalized in etym_connector_words && return false
		haskey(table.languages, normalized) && return false
		normalized in table.skip && return false
	end
	true
end

function extract_gloss(gap::AbstractString, boundary_required::Bool,
		table::EtymLanguageTable)::Tuple{String, String}
	stripped = lstrip(gap)
	startswith(stripped, ',') || return "", String(gap)
	boundary = findfirst(character -> character in (';', '('), stripped)
	if boundary === nothing
		boundary_required && return "", String(gap)
		candidate = stripped[nextind(stripped, 1):end]
		remainder = ""
	else
		candidate = stripped[nextind(stripped, 1):prevind(stripped, boundary)]
		remainder = stripped[boundary:end]
	end
	gloss = strip(rstrip(strip(candidate), '.'))
	(isempty(gloss) || !gloss_qualifies(gloss, table)) && return "", String(gap)
	String(gloss), String(remainder)
end

function emit_cluster!(segments::Vector{EtymSegment}, cluster::EtymCluster,
		pending::EtymPending, table::EtymLanguageTable, chunk_end::Bool)
	cit_type = cit_type_of(pending)
	defaulted = is_defaulted(pending)
	for (index, cue) in enumerate(cluster.cues)
		index > 1 && push!(segments,
			EtymConnector(cluster.connectors[min(index - 1, length(cluster.connectors))]))
		push!(segments, EtymCit(cit_type, cue.code, cue, cluster.fictif,
			copy(cluster.forms), "", defaulted))
	end
	if !isempty(cluster.trailing)
		trailing_text = join(cluster.trailing, ' ')
		if chunk_end && gloss_qualifies(strip(rstrip(strip(trailing_text), '.')), table)
			segments[end] = with_gloss(segments[end], strip(rstrip(strip(trailing_text), '.')))
		else
			push_prose!(segments, trailing_text)
		end
	end
	reset_pending!(pending)
end

function process_chunk!(segments::Vector{EtymSegment}, pending::EtymPending,
		chunk::AbstractString, table::EtymLanguageTable; adjacent_event::Symbol)
	text = strip(chunk)
	isempty(text) && return
	if occursin('<', text)
		push_prose!(segments, text)
		return
	end
	if adjacent_event == :anchor
		label_match = match(etym_reference_label_tail, text)
		if label_match !== nothing
			pending.xr_label = String(label_match.captures[1])
			text = strip(text[1:prevind(text, label_match.offset)])
			isempty(text) && return
		end
	end
	tokens = String[token for token in split(text) if !is_punctuation_token(token)]
	isempty(tokens) && return

	lead = 1
	while lead <= length(tokens) && normalize_etym_token(tokens[lead]) in etym_connector_words
		lead += 1
	end
	connectors = tokens[1:lead - 1]
	rest = tokens[lead:end]
	derivational = occursin(etym_derivational_pattern, lowercase(join(tokens, ' ')))

	if isempty(rest)
		if adjacent_event == :form
			push!(segments, EtymConnector(join(connectors, ' ')))
			pending.derivational |= derivational
		else
			push_prose!(segments, join(connectors, ' '))
		end
		return
	end

	cluster = parse_cue_cluster(rest, table)
	if cluster === nothing
		rescue_start = 0
		for position in reverse(2:length(rest))
			cue, consumed, key = match_cue_at(rest, position, table)
			(cue === nothing || !occursin('.', key)) && continue
			position + consumed - 1 <= length(rest) || continue
			candidate = parse_cue_cluster(rest[position:end], table)
			candidate === nothing && continue
			rescue_start = position
			cluster = candidate
			break
		end
		if rescue_start > 0
			push_prose!(segments, join(vcat(connectors, rest[1:rescue_start - 1]), ' '))
			if adjacent_event == :form
				pending.prose_seen = true
				pending.derivational |= derivational
			end
			finish_cluster!(segments, pending, cluster, table;
				adjacent_event, chunk_end = true, derivational)
			return
		end
		last_token = rest[end]
		last_normalized = normalize_etym_token(last_token)
		suspect = adjacent_event == :form &&
			!haskey(table.languages, last_normalized) &&
			!(last_normalized in table.skip) &&
			(endswith(strip(last_token, [',', ' ']), '.') ||
				(length(rest) == 1 && length(last_normalized) <= 4))
		if suspect
			length(tokens) > 1 && push_prose!(segments, join(tokens[1:end - 1], ' '))
			push!(segments, EtymSuspect(String(strip(last_token, [',', ' '])), String(first(text, 120))))
			pending.derivational |= adjacent_event == :form && derivational
		else
			push_prose!(segments, text)
			if adjacent_event == :form
				pending.prose_seen = true
				pending.derivational |= derivational
				pending.language_hint = full_name_language_hint(rest, table)
			end
		end
		return
	end

	!isempty(connectors) && push!(segments, EtymConnector(join(connectors, ' ')))
	finish_cluster!(segments, pending, cluster, table;
		adjacent_event, chunk_end = true, derivational)
end

function finish_cluster!(segments::Vector{EtymSegment}, pending::EtymPending,
		cluster::EtymCluster, table::EtymLanguageTable;
		adjacent_event::Symbol, chunk_end::Bool, derivational::Bool)
	pending.derivational |= derivational
	if isempty(cluster.forms)
		if adjacent_event == :form
			append!(pending.cues, cluster.cues)
			append!(pending.connectors, cluster.connectors)
			pending.fictif |= cluster.fictif
		else
			push_prose!(segments, join([cue.printed for cue in cluster.cues], ' '))
			reset_pending!(pending)
		end
	else
		emit_cluster!(segments, cluster, pending, table, chunk_end)
	end
end

function process_gap!(segments::Vector{EtymSegment}, pending::EtymPending,
		gap::AbstractString, table::EtymLanguageTable;
		previous_form::Bool, next_event::Symbol)
	remaining = gap
	if previous_form && !isempty(segments) && segments[end] isa EtymCit
		gloss, remaining = extract_gloss(gap, next_event != :none, table)
		isempty(gloss) || (segments[end] = with_gloss(segments[end], gloss))
	end
	chunks = split(remaining, r"[;()]")
	for (index, chunk) in enumerate(chunks)
		adjacent = index == length(chunks) ? next_event : :none
		process_chunk!(segments, pending, chunk, table; adjacent_event = adjacent)
	end
end

# ── Event consumption ────────────────────────────────────────────

function emit_form_event!(segments::Vector{EtymSegment}, pending::EtymPending,
		event::EtymEvent)
	if !isempty(pending.cues)
		for (index, cue) in enumerate(pending.cues)
			index > 1 && push!(segments,
				EtymConnector(pending.connectors[min(index - 1, length(pending.connectors))]))
			push!(segments, EtymCit(cit_type_of(pending), cue.code, cue,
				pending.fictif, copy(event.forms), "", is_defaulted(pending)))
		end
	else
		language = isempty(event.language) ? pending.language_hint : event.language
		push!(segments, EtymCit(cit_type_of(pending), language, nothing,
			pending.fictif, copy(event.forms), "", is_defaulted(pending)))
	end
	reset_pending!(pending)
end

function emit_anchor_event!(segments::Vector{EtymSegment}, pending::EtymPending,
		event::EtymEvent)
	if isempty(pending.xr_label)
		push!(segments, EtymProse("<a ref=\"$(event.target)\">$(event.printed)</a>"))
	else
		push!(segments, EtymCrossReference(pending.xr_label, event.target, event.printed))
	end
	reset_pending!(pending)
end

# ── Entry point ──────────────────────────────────────────────────
# Segmentation splits the content string, so tag pairs outside the recognized
# event inventory (other Gannaz markup, anchors nested inside wrappers) could
# be severed across segments. Such content falls back to a single prose
# segment — byte-identical to pre-W4 emission, where the whole line passed
# through etym_markup together and pairs stayed intact.

function etym_residual(content::String, events::Vector{EtymEvent})::String
	bytes = Vector{UInt8}(codeunits(content))
	for event in events
		bytes[event.range] .= UInt8(' ')
	end
	String(bytes)
end

function segmentable(content::String, events::Vector{EtymEvent})::Bool
	occursin('<', etym_residual(content, events)) && return false
	all(event -> !any(form -> occursin('<', form), event.forms), events)
end

function segment_etymology(content::String,
		table::EtymLanguageTable = etym_language_table)::Vector{EtymSegment}
	stripped = strip(content)
	isempty(stripped) && return EtymSegment[]
	events = etym_events(content)
	isempty(events) && return EtymSegment[EtymProse(String(stripped))]
	segmentable(content, events) || return EtymSegment[EtymProse(String(stripped))]

	segments = EtymSegment[]
	pending = EtymPending()
	cursor = 1
	previous_form = false
	for event in events
		gap = cursor <= first(event.range) - 1 ?
			content[cursor:prevind(content, first(event.range))] : ""
		process_gap!(segments, pending, gap, table;
			previous_form, next_event = event.kind)
		if event.kind == :form
			emit_form_event!(segments, pending, event)
			previous_form = true
		else
			emit_anchor_event!(segments, pending, event)
			previous_form = false
		end
		cursor = last(event.range) + 1
	end
	tail = cursor <= ncodeunits(content) ? content[cursor:end] : ""
	process_gap!(segments, pending, tail, table; previous_form, next_event = :none)
	segments
end
