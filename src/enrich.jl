# ── Resolve authors ──────────────────────────────────────────────
# Walks citations in document order within each entry, propagating
# the last named author forward through "ID." references.

function collect_citations!(out::Vector{Citation}, indent::Indent)
	append!(out, indent.citations)
	for child in indent.children
		collect_citations!(out, child)
	end
end

function collect_citations!(out::Vector{Citation}, rub::Rubrique)
	append!(out, rub.citations)
	for indent in rub.indents
		collect_citations!(out, indent)
	end
end

function citations_in_order(entry::Entry)::Vector{Citation}
	out = Citation[]
	for el in entry.body
		if el isa Sense
			append!(out, el.citations)
			for indent in el.indents
				collect_citations!(out, indent)
			end
			for rub in el.rubriques
				collect_citations!(out, rub)
			end
		end
	end
	for rub in entry.rubriques
		collect_citations!(out, rub)
	end
	out
end

function resolve_authors!(entry::Entry)::Int
	all_citations = citations_in_order(entry)
	last_author = ""
	resolved = 0

	for cit in all_citations
		if cit.author == "ID." && !isempty(last_author)
			cit.resolved_author = last_author
			resolved += 1
		elseif !isempty(cit.author) && cit.author != "ID."
			last_author = cit.author
			cit.resolved_author = cit.author
		else
			cit.resolved_author = cit.author
		end
	end
	resolved
end

function resolve_all_authors!(entries::Vector{Entry})
	total = 0
	unresolved = 0
	for entry in entries
		total += resolve_authors!(entry)
		for cit in citations_in_order(entry)
			if cit.author == "ID." && isempty(cit.resolved_author)
				unresolved += 1
			end
		end
	end
	@info "Resolved $total ID. citations"
	unresolved > 0 && @warn "$unresolved ID. citations had no antecedent"
end

# ── Classify indents ─────────────────────────────────────────────

# ── Verdicts (external classification overrides) ─────────────────
# CSV keyed on (file, line). An llm_confidence column is tolerated
# if present but ignored; confidence is no longer part of the model.

struct Verdict
	role::IndentRole
	check::String
end

const verdict_key = Tuple{String, Int}
const VerdictDict = Dict{verdict_key, Verdict}

const role_names = Dict{String, IndentRole}(
	"Figurative" => Figurative(),
	"DomainLabel" => DomainLabel(),
	"NatureLabel" => NatureLabel(),
	"CrossReference" => CrossReference(),
	"RegisterLabel" => RegisterLabel(),
	"Proverb" => Proverb(),
	"VoiceTransition" => VoiceTransition(),
	"Locution" => Locution(),
	"Unclassified" => Unclassified(),
)

function load_verdicts(path::String)::VerdictDict
	verdicts = VerdictDict()
	isfile(path) || return verdicts
	lines = readlines(path)
	isempty(lines) && return verdicts
	header = split(first(lines), ',')
	col = Dict(strip(h) => i for (i, h) in enumerate(header))
	for line in lines[2:end]
		isempty(strip(line)) && continue
		fields = split(line, ',')
		file = strip(fields[col["file"]])
		line_num = parse(Int, strip(fields[col["line"]]))
		check_col = get(col, "check", nothing)
		check = check_col !== nothing ? strip(get(fields, check_col, "")) : ""
		role_str = strip(fields[col["llm_role"]])
		role = get(role_names, role_str, nothing)
		if role === nothing
			@warn "Unknown role in verdicts" role_str file line_num
			continue
		end
		verdicts[(file, line_num)] = Verdict(role, check)
	end
	@info "Loaded $(length(verdicts)) verdicts from $path"
	verdicts
end

function apply_verdict!(indent::Indent, verdicts::VerdictDict)::Bool
	indent.source === nothing && return false
	key = (indent.source.file, indent.source.line)
	verdict = get(verdicts, key, nothing)
	verdict === nothing && return false
	if !isempty(verdict.check)
		plain = strip_tags(indent.content)
		if !startswith(plain, verdict.check)
			@warn "Verdict check mismatch" key verdict.check actual=first(plain, 30)
			return false
		end
	end
	classify!(indent, verdict.role, LlmAssisted)
	true
end

function classify!(indent::Indent, role::IndentRole, method::ClassificationMethod)
	indent.classification = Classification(role = role, method = method)
end

function role_of(indent::Indent)::Union{Nothing, IndentRole}
	indent.classification === nothing ? nothing : indent.classification.role
end

matches_any(patterns::Vector{Regex}, text::AbstractString) =
	any(p -> occursin(p, text), patterns)

# ── Tier A: deterministic (tag-based) ────────────────────────────

const cross_ref_leading_patterns = [
	r"^(voy\.|v\.|voyez\b)"i,
]

const cross_ref_trailing_patterns = [
	r",\s*voy\.\s*$"i,
]

function classify_deterministic!(indent::Indent)::Bool
	c = indent.content

	if occursin("<semantique type=\"indicateur\">Fig.", c)
		classify!(indent, Figurative(), Deterministic)
		return true
	end

	if occursin("<semantique type=\"domaine\">", c)
		classify!(indent, DomainLabel(), Deterministic)
		return true
	end

	if occursin("<nature>", c)
		classify!(indent, NatureLabel(), Deterministic)
		return true
	end

	if occursin("<exemple>", c)
		if matches_any(proverb_patterns, strip_tags(c))
			classify!(indent, Proverb(), Deterministic)
		else
			classify!(indent, Locution(), Deterministic)
		end
		return true
	end

	if occursin("<a ref=", c)
		plain = strip_tags(c)
		if length(plain) < 120
			if matches_any(cross_ref_leading_patterns, plain) ||
			   matches_any(cross_ref_trailing_patterns, plain)
				classify!(indent, CrossReference(), Deterministic)
				return true
			end
		end
	end

	false
end

# ── Tier B: heuristic (text patterns) ────────────────────────────

const register_patterns = [
	r"^populaire(ment)?\b"i,
	r"^(familièr|vulgair|ironiqu|burlesqu|poétiqu)ement\b"i,
	r"^plaisamment\b"i,
	r"^par (euphémisme|exagération|ironie|dérision|extension|analogie|métaphore|plaisanterie|antiphrase)\b"i,
	r"^néologisme\b"i,
	r"^(très )?peu usité\b"i,
	r"^hors d'usage\b"i,
	r"^tombé en désuétude\b"i,
	r"^il est (familier|vieux|populaire|inusité|hors d'usage)\b"i,
	r"^il n'est plus usité\b"i,
	r"^il (a vieilli|vieillit)\b"i,
	r"^ce mot (est|a vieilli)\b"i,
	r"^ce sens a vieilli\b"i,
	r"^cet emploi (vieillit|a vieilli)\b"i,
	r"^(mot|terme) (vieilli|vieux|familier|populaire|inusité|bas)\b"i,
]

const proverb_patterns = [
	r"^prov\.\s"i,
	r"^proverbe\b"i,
	r"^proverbialement\b"i,
]

const voice_transition_patterns = [
	r"^v\.\s*(n|a|réfl)\b"i,
	r"^se\s+conjugue\b"i,
	r"^(absolument|substantivement|adverbialement|adjectivement|intransitivement|neutralement|impersonnellement|activement)\b"i,
]

const figurative_patterns = [
	r"^fig\.\s"i,
]

const voice_transition_label_only_patterns = [
	r"^au (pluriel|féminin|singulier|masc(\.|ulin)?|fém(\.|inin)?)\.?\s*$"i,
	r"^avec un nom de [^,.]*\.?\s*$"i,
]

const register_label_only_patterns = [
	r"^(familière?|familier|vieux|vieillie?|rare|bas(se)?|vulgaire|triviale?|inusitée?)\.?\s*$"i,
]

const strong_transition_pattern = r"^(S'[A-ZÉÈÊÀÂÎÏÔÙÛÜÇ].+),\s+(v\.\s*.+)"

const form_pos_pattern = r"^([A-ZÉÈÊÀÂÎÏÔÙÛÜÇ][A-ZÉÈÊÀÂÎÏÔÙÛÜÇ '\-]+),\s+(v\.\s*(?:n|a|réfl)|s\.\s*[mf]|adj)\b"

function is_transition_content(content::AbstractString)::Bool
	occursin("<nature>", content) && return true
	plain = strip_tags(content)
	matches_any(voice_transition_patterns, plain) && return true
	matches_any(voice_transition_label_only_patterns, plain) && return true
	occursin(strong_transition_pattern, plain) && return true
	occursin(form_pos_pattern, plain) && return true
	false
end

function classify_heuristic!(indent::Indent)::Bool
	plain = strip_tags(indent.content)

	if matches_any(proverb_patterns, plain)
		classify!(indent, Proverb(), Heuristic)
		return true
	end

	if matches_any(register_patterns, plain)
		classify!(indent, RegisterLabel(), Heuristic)
		return true
	end

	if matches_any(voice_transition_patterns, plain)
		classify!(indent, VoiceTransition(), Heuristic)
		return true
	end

	if matches_any(figurative_patterns, plain)
		classify!(indent, Figurative(), Heuristic)
		return true
	end

	if matches_any(voice_transition_label_only_patterns, plain)
		classify!(indent, VoiceTransition(), Heuristic)
		return true
	end

	if matches_any(register_label_only_patterns, plain)
		classify!(indent, RegisterLabel(), Heuristic)
		return true
	end

	classify!(indent, Unclassified(), Heuristic)
	true
end

# ── Combined classifier ──────────────────────────────────────────

function classify_indent!(indent::Indent, verdicts::VerdictDict = VerdictDict())
	apply_verdict!(indent, verdicts) ||
		classify_deterministic!(indent) ||
		classify_heuristic!(indent)
	for child in indent.children
		classify_indent!(child, verdicts)
	end
end

function each_indent(f::Function, entry::Entry)
	for el in entry.body
		if el isa Sense
			for indent in el.indents
				_walk_indents(indent, f)
			end
		end
	end
end

function _walk_indents(indent::Indent, f::Function)
	f(indent)
	for child in indent.children
		_walk_indents(child, f)
	end
end

function classify_all!(entries::Vector{Entry}, verdicts::VerdictDict = VerdictDict())
	counts = Dict{String, Int}()
	for entry in entries
		for el in entry.body
			if el isa Sense
				for indent in el.indents
					classify_indent!(indent, verdicts)
				end
			end
		end
		each_indent(entry) do indent
			role = role_of(indent)
			name = role === nothing ? "unknown" : string(typeof(role))
			counts[name] = get(counts, name, 0) + 1
		end
	end

	total = sum(values(counts))
	unknown = get(counts, "unknown", 0)
	@info "Classified $(total - unknown)/$total ($(round((total - unknown) / total * 100; digits=1))%)"
	for (role, count) in sort(collect(counts); by = last, rev = true)
		@info "  $role: $count"
	end
	counts
end

# ── Extract locutions ────────────────────────────────────────────

const exemple_pattern = r"<exemple>(.*?)</exemple>"
const reflexive_pattern = r"^S'[A-ZÉÈÊÀÂÎÏÔÙÛÜÇ].*,\s*v\.\s*réfl\b"

function extract_locution!(indent::Indent)
	role_of(indent) isa Locution || return :skip

	plain = strip_tags(indent.content)

	if occursin(reflexive_pattern, plain)
		classify!(indent, VoiceTransition(), Heuristic)
		return :reclassified
	end

	m = match(exemple_pattern, indent.content)
	if m !== nothing
		indent.canonical_form = strip(m.captures[1])
		indent.canonical_form_source = :exemple
		return :extracted
	end

	if !occursin(',', plain)
		return :skip
	end

	form = strip(first(split(plain, ','; limit = 2)))
	if length(form) > 60
		return :skip
	end
	indent.canonical_form = form
	indent.canonical_form_source = :prose
	:extracted
end

# ── Extract proverb forms ────────────────────────────────────────
# Proverb indents migrate to relatedEntry in TEI and need a lemma form. The
# form is the proverb text up to the gloss introducer; splitting at a bare
# comma would truncate proverbs with internal commas, so only explicit
# introducers cut. A proverb with no gloss is self-glossing: the whole text is
# the form and the def repeats it, which is odd but honest to the print.

const proverb_lead_pattern = r"^\s*prov(?:erbe|erbialement)?\.?\s*[:.]?\s*"i
const proverb_gloss_introducer = r",?\s*(?:c\.-à-d\.|c'est-à-dire|se dit|pour dire|signifie)"i

function extract_proverb_form!(indent::Indent)::Bool
	role_of(indent) isa Proverb || return false
	isempty(indent.canonical_form) || return false
	printed = match(exemple_pattern, indent.content)
	if printed !== nothing
		indent.canonical_form = strip(printed.captures[1])
		indent.canonical_form_source = :exemple
		return true
	end
	body = replace(strip_tags(indent.content), proverb_lead_pattern => ""; count = 1)
	m = match(proverb_gloss_introducer, body)
	form = m === nothing ? body : body[1:prevind(body, m.offset)]
	form = String(strip(rstrip(strip(form), ['.', ',', ';', ':'])))
	isempty(form) && return false
	indent.canonical_form = form
	indent.canonical_form_source = :prose
	true
end

function extract_all_proverb_forms!(entries::Vector{Entry})
	extracted = 0
	for entry in entries
		each_indent(entry) do indent
			extract_proverb_form!(indent) && (extracted += 1)
		end
	end
	@info "Extracted proverb forms: $extracted"
end

# ── Metonymic-gloss discriminator ────────────────────────────────
# Review-flag predicate over locution-classified indents: a gloss opening with
# a definite article reads as a noun phrase naming what the headword denotes (a
# metonymic sub-sense) rather than defining a fixed expression. The bare
# article test cannot distinguish article+noun from clitic pronoun+verb ("le
# traiter d'ignorant"), so matches route to review_queue rather than
# restructuring; the hand-labeled population is uniform today.

const metonymic_gloss_pattern = r"^(?:(?:les|la|le)\s+|l')\p{L}"i

function locution_gloss(indent::Indent)::String
	plain = replace(strip_tags(indent.content), proverb_lead_pattern => ""; count = 1)
	form = indent.canonical_form
	if !isempty(form) && startswith(lowercase(plain), lowercase(form))
		plain = lstrip(chop(plain; head = length(form), tail = 0), [' ', ',', '.', ';', ':'])
	end
	String(strip(plain))
end

function is_metonymic_gloss(indent::Indent)::Bool
	role_of(indent) isa Locution || return false
	occursin(metonymic_gloss_pattern, locution_gloss(indent))
end

function extract_all_locutions!(entries::Vector{Entry})
	extracted = 0
	reclassified = 0
	skipped = 0

	for entry in entries
		each_indent(entry) do indent
			result = extract_locution!(indent)
			if result == :reclassified
				reclassified += 1
			elseif result == :extracted
				extracted += 1
			elseif result == :skip && role_of(indent) isa Locution
				skipped += 1
			end
		end
	end

	@info "Extracted canonical forms: $extracted"
	@info "Reclassified to voice_transition: $reclassified"
	@info "Skipped (no clear form): $skipped"
end

# ── Combined enrichment entry point ──────────────────────────────

function enrich!(entries::Vector{Entry}; verdicts_path::Union{Nothing, String} = nothing)
	@info "Phase 2: Resolve authors"
	resolve_all_authors!(entries)

	verdicts = verdicts_path !== nothing ? load_verdicts(verdicts_path) : VerdictDict()

	@info "Phase 3: Classify indents"
	classify_all!(entries, verdicts)

	@info "Phase 4: Extract locutions"
	extract_all_locutions!(entries)
	extract_all_proverb_forms!(entries)
end
