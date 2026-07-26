const object_language = "fr-x-lit19c"

# ── Markup conversion ────────────────────────────────────────────
# Converts Gannaz inline markup to TEI equivalents.

const markup_substitutions = [
	r"<semantique type=\"domaine\">(.*?)</semantique>"s => s"<usg type=\"domain\">\1</usg>",
	r"<semantique type=\"indicateur\">(.*?)</semantique>"s => s"<usg type=\"sem\">\1</usg>",
	r"<semantique>(.*?)</semantique>"s => s"<usg type=\"sem\">\1</usg>",
	r"<exemple>(.*?)</exemple>"s => s"<mentioned>\1</mentioned>",
	r"<nature>(.*?)</nature>"s => s"<usg type=\"gram\">\1</usg>",
]

function markup_to_tei(markup::String)::String
	result = markup
	for (pattern, replacement) in markup_substitutions
		result = replace(result, pattern => replacement)
	end
	result = convert_cross_references(result)
	result = lift_reference_labels(result)
	result = convert_italics(result)
	lowercase_usg_content(result)
end

# ── Cross-references ─────────────────────────────────────────────
# Gannaz's <a ref="..."> carries the printed headword, not an emitted xml:id.
# Routing it through make_id (preserving a trailing homograph index) lifts
# target resolution from 56.1% to 79.7% of 14,931 references. The residue is
# the ID-deduplication class, where a bare headword cannot choose between
# chien_1 and chien_2; that needs a mapping table and is deferred with P2.

const anchor_pattern = r"<a ref=\"([^\"]*)\">(.*?)</a>"s

const reference_label_pattern =
	r"\b((?:[Vv]oy(?:ez)?|[Cc]f|[Cc]omparez)\.?)\s*(<xr type=\"related\">)"

function make_reference_id(reference::AbstractString)::String
	base = String(first(split(reference, '#')))
	matched = match(r"^(.*)\.(\d+)$", base)
	matched === nothing && return make_id(base)
	"$(make_id(String(matched.captures[1]))).$(matched.captures[2])"
end

function convert_cross_references(markup::AbstractString)::String
	replace(markup, anchor_pattern => function (matched_text)
		parts = match(anchor_pattern, matched_text)
		target = escape_xml(make_reference_id(parts.captures[1]))
		"<xr type=\"related\"><ref type=\"entry\" target=\"#$(target)\">$(parts.captures[2])</ref></xr>"
	end)
end

function lift_reference_labels(markup::AbstractString)::String
	replace(markup, reference_label_pattern => s"\2<lbl>\1</lbl>")
end

function lowercase_usg_content(s::AbstractString)::String
	buf = IOBuffer()
	last_end = 1
	for m in eachmatch(r"(<usg\b[^>]*>)(.*?)(</usg>)"s, s)
		print(buf, s[last_end:prevind(s, m.offset)])
		print(buf, m.captures[1], lowercase(m.captures[2]), m.captures[3])
		last_end = m.offset + ncodeunits(m.match)
	end
	print(buf, s[last_end:end])
	String(take!(buf))
end

function lowercase_text_nodes(s::AbstractString)::String
	join(
		startswith(part, '<') ? part : lowercase(part)
		for part in split_preserving(s, r"<[^>]+>")
	)
end

function split_preserving(s::AbstractString, pattern::Regex)::Vector{String}
	parts = String[]
	last_end = 1
	for m in eachmatch(pattern, s)
		if m.offset > last_end
			push!(parts, s[last_end:prevind(s, m.offset)])
		end
		push!(parts, m.match)
		last_end = m.offset + ncodeunits(m.match)
	end
	if last_end <= ncodeunits(s)
		push!(parts, s[last_end:end])
	end
	parts
end

# Latin italics and emphatic italics share the </i> close tag, so independent
# regex passes mispair when one <i> nests inside another. A single pass over the
# tag stream tracks open <i> tags on a stack and emits the matching close by kind.
function convert_italics(s::AbstractString)::String
	buffer = IOBuffer()
	stack = Symbol[]
	for token in split_preserving(s, r"<[^>]+>")
		if token == "<i lang=\"la\">"
			push!(stack, :foreign)
			print(buffer, "<foreign xml:lang=\"la\">")
		elseif token == "<i>"
			push!(stack, :mentioned)
			print(buffer, "<mentioned>")
		elseif token == "</i>"
			kind = isempty(stack) ? :verbatim : pop!(stack)
			print(buffer, kind === :foreign ? "</foreign>" :
				kind === :mentioned ? "</mentioned>" : "</i>")
		elseif startswith(token, "<i ") || startswith(token, "<i\t") || startswith(token, "<i\n")
			push!(stack, :verbatim)
			print(buffer, token)
		else
			print(buffer, token)
		end
	end
	String(take!(buffer))
end

function is_balanced(s::AbstractString)::Bool
	depth = 0
	for token in split_preserving(s, r"<[^>]+>")
		startswith(token, "<") || continue
		if startswith(token, "</")
			depth -= 1
			depth < 0 && return false
		elseif !endswith(token, "/>")
			depth += 1
		end
	end
	depth == 0
end

function strip_usg_tags(s::AbstractString)::String
	replace(s, r"<usg\b[^>]*>(.*?)</usg>"s => s"\1")
end

# ── Label splitting ──────────────────────────────────────────────

function split_label(tei_content::AbstractString)::Tuple{String, String}
	m = match(r"^<gramGrp><gram\b[^>]*>(.*?)</gram></gramGrp>\s*"s, tei_content)
	if m !== nothing
		label = lowercase(strip_usg_tags(strip(m.captures[1])))
		remaining = replace(tei_content[m.offset + ncodeunits(m.match):end], r"^[,;:\s]+" => "")
		return (label, strip(remaining))
	end
	m = match(r"^<usg\b[^>]*>(.*?)</usg>\s*"s, tei_content)
	if m !== nothing
		label = lowercase_text_nodes(strip_usg_tags(strip(m.captures[1])))
		remaining = replace(tei_content[m.offset + ncodeunits(m.match):end], r"^[,;:\s]+" => "")
		return (label, strip(remaining))
	end
	m = match(r"^Fig\.\s*", tei_content)
	if m !== nothing
		remaining = replace(tei_content[m.offset + ncodeunits(m.match):end], r"^[,;:\s]+" => "")
		return ("fig.", strip(remaining))
	end
	(lowercase_text_nodes(strip_usg_tags(tei_content)), "")
end

const leading_usg_pattern = r"^<usg\b[^>]*type=\"([^\"]*)\"[^>]*>(.*?)</usg>[,;:\s]*"s
const inline_usg_pattern = r"<usg\b[^>]*type=\"([^\"]*)\"[^>]*>(.*?)</usg>"s
const routed_usg_types = Set(["sem", "register", "gram"])

# Leading labels are structural siblings of <def>, so a grammatical reading
# may become <gramGrp> here. Anything already carrying a schema-valid type
# (domain) is passed through untouched.
function route_label_markup(usg_type::AbstractString, printed::AbstractString)::Vector{String}
	usg_type in routed_usg_types || return [usg_markup(UsgTarget(String(usg_type), ""), printed)]
	[
		target isa UsgTarget ? usg_markup(target, printed) : gram_markup(target)
		for target in route_content(printed)
	]
end

function split_def_usg(tei_content::AbstractString)::Tuple{Vector{String}, String}
	usg_elements = String[]
	remaining = tei_content
	while true
		m = match(leading_usg_pattern, remaining)
		m === nothing && break
		append!(usg_elements, route_label_markup(m.captures[1], lowercase_text_nodes(m.captures[2])))
		remaining = strip(remaining[m.offset + ncodeunits(m.match):end])
	end
	(usg_elements, remaining)
end

# <def> admits only text, gLike, hiLike, ptrLike, segLike, gloss and xr, so a
# <usg> surviving mid-prose stays a <usg> whatever its reading: retyping clears
# the invalid-@type signature, while the position error is W3's def-extraction.
function remap_inline_usg(tei_content::AbstractString)::String
	replace(tei_content, inline_usg_pattern => function (matched_text)
		parts = match(inline_usg_pattern, matched_text)
		usg_type, printed = parts.captures[1], parts.captures[2]
		usg_type in routed_usg_types || return matched_text
		targets = route_content(printed)
		length(targets) == 1 && return usg_only_markup(targets[1], printed)
		join(usg_only_markup(target, printed) for target in targets)
	end)
end

definition_markup(tei_content::AbstractString)::String = remap_inline_usg(tei_content)

# ── Gram splitting (two-step: structural split, then classify) ───

struct GramSplit
	pre_text::String
	label_text::String
	def_text::String
	pre_kind::Symbol
end

function split_gram(tei_content::AbstractString)::GramSplit
	m = match(r"(.*?)<usg type=\"gram\">(.*?)</usg>(.*)"s, tei_content)
	m === nothing && return GramSplit("", "", "", :none)
	pre_raw = strip(replace(strip(m.captures[1]), r"[,;:\s]+$" => ""))
	label = strip(m.captures[2])
	def_raw = strip(replace(strip(m.captures[3]), r"^[,;:\s]+" => ""))
	pre_kind = classify_pre_text(pre_raw, label)
	GramSplit(pre_raw, label, def_raw, pre_kind)
end

function classify_pre_text(pre_text::AbstractString, label_text::AbstractString)::Symbol
	isempty(pre_text) && return :none
	if match(r"^[Ss][e''\u2019]", pre_text) !== nothing && occursin("réfl", label_text)
		return :reflexive_form
	end
	if occursin(r"loc\.\s*(adv|prépos|conj)|locut\."i, label_text)
		return :locution_form
	end
	:headword_echo
end

# ── Bare-text transition splitting ──────────────────────────────

const bare_label_patterns = [
	r"^substantivement\b"i,
	r"^absolument\b"i,
	r"^adjectivement\b"i,
	r"^adverbialement\b"i,
	r"^intransitivement\b"i,
	r"^neutralement\b"i,
	r"^impersonnellement\b"i,
	r"^activement\b"i,
	r"^v\.\s*(?:n|a|réfl)\b"i,
	r"^se\s+conjugue\b"i,
	r"^au\s+(?:pluriel|féminin|singulier|figuré|masculin)\b"i,
	r"^familièrement\b"i,
	r"^populaire(?:ment)?\b"i,
	r"^vulgairement\b"i,
	r"^ironiquement\b"i,
	r"^plaisamment\b"i,
	r"^poétiquement\b"i,
	r"^burlesquement\b"i,
	r"^par\s+(?:euphémisme|exagération|ironie|dérision|extension|analogie|métaphore|plaisanterie|antiphrase)\b"i,
	r"^néologisme\b"i,
	r"^(?:très\s+)?peu\s+usité\b"i,
	r"^hors\s+d'usage\b"i,
	r"^tombé\s+en\s+désuétude\b"i,
	r"^il\s+est\s+(?:familier|vieux|populaire|inusité|hors\s+d'usage)\b"i,
	r"^il\s+n'est\s+plus\s+usité\b"i,
	r"^il\s+(?:a\s+vieilli|vieillit)\b"i,
	r"^ce\s+mot\s+(?:est|a\s+vieilli)\b"i,
	r"^ce\s+sens\s+a\s+vieilli\b"i,
	r"^cet\s+emploi\s+(?:vieillit|a\s+vieilli)\b"i,
	r"^(?:mot|terme)\s+(?:vieilli|vieux|familier|populaire|inusité|bas)\b"i,
]

const bare_label_tail = r"^((?:\s+et\b[^,.:]*)*)\s*([,.:])\s*(.*)"s

function split_bare_transition(text::AbstractString)::Union{Nothing, Tuple{String, String}}
	for pattern in bare_label_patterns
		root = match(pattern, text)
		root === nothing && continue
		remainder = SubString(text, root.offset + ncodeunits(root.match))
		tail = match(bare_label_tail, remainder)
		tail === nothing && continue
		label = strip(string(root.match) * tail.captures[1])
		def_text = strip(tail.captures[3])
		isempty(def_text) && continue
		return (lowercase(label), def_text)
	end
	nothing
end

# ── XML helpers ──────────────────────────────────────────────────

function id_attr(sense_id::String)::String
	isempty(sense_id) ? "" : " xml:id=\"$(escape_xml(sense_id))\""
end

# relatedEntry ids: positional sense id + a slug of the canonical form
# (e.g. cabinet_s4.1.tenir_cabinet). Falls back to the positional id when no
# form is available. Not yet wired into emission; consumed by W3's <re
# type="locution"> → <entry type="relatedEntry"> migration.
function related_entry_id(positional_id::AbstractString, canonical_form::AbstractString)::String
	slug = slugify(canonical_form)
	isempty(slug) ? String(positional_id) : "$(positional_id).$(slug)"
end

pad(level::Int) = "  " ^ level

# An unparsed POS string keeps the single untyped-content <gram type="pos">
# it has today: still schema-valid, just unsplit. 0.16% of 77,391 entry-level
# strings take this path.
function pos_group_markup(pos::AbstractString)::String
	elements = parse_pos(pos)
	elements === nothing || return gram_markup(elements)
	"<gramGrp><gram type=\"pos\">$(escape_xml(pos))</gram></gramGrp>"
end

# ── Citation emission ────────────────────────────────────────────

function emit_citation(io::IO, cit::Citation, level::Int)
	p = pad(level)
	author = isempty(cit.resolved_author) ? cit.author : cit.resolved_author
	text = markup_to_tei(cit.text)
	hidden = isempty(cit.hide) ? "" : " ana=\"hidden\""

	println(io, "$(p)<cit type=\"example\"$(hidden)>")
	println(io, "$(p)  <quote>$(text)</quote>")
	if !isempty(author) || !isempty(cit.reference)
		println(io, "$(p)  <bibl>")
		!isempty(author) && println(io, "$(p)    <author>$(escape_xml(author))</author>")
		!isempty(cit.reference) && println(io, "$(p)    <biblScope>$(escape_xml(cit.reference))</biblScope>")
		println(io, "$(p)  </bibl>")
	end
	println(io, "$(p)</cit>")
end

function emit_citations(io::IO, citations::Vector{Citation}, level::Int)
	for cit in citations
		emit_citation(io, cit, level)
	end
end

# ── Indent emission (dispatched on IndentRole) ───────────────────

function emit_indent(io::IO, indent::Indent, level::Int, sense_id::String = "")
	role = role_of(indent)
	if role === nothing
		emit_indent(io, indent, Unclassified(), level, sense_id)
	else
		emit_indent(io, indent, role, level, sense_id)
	end
end

function emit_children(io::IO, children::Vector{Indent}, level::Int, parent_id::String)
	for (i, child) in enumerate(children)
		child_id = isempty(parent_id) ? "" : "$(parent_id).$(i)"
		emit_indent(io, child, level, child_id)
	end
end

function emit_label_sense(io::IO, label::String, usg_type::String, def_text::String,
		citations::Vector{Citation}, children::Vector{Indent},
		level::Int; sense_id::String = "", extra_attrs::String = "")
	p = pad(level)
	label = strip_usg_tags(label)
	println(io, "$(p)<sense$(id_attr(sense_id))$(extra_attrs)>")
	for element in route_label_markup(usg_type, label)
		println(io, "$(p)  $(element)")
	end
	if !isempty(def_text)
		usg_els, clean_def = split_def_usg(def_text)
		for el in usg_els
			println(io, "$(p)  $(el)")
		end
		!isempty(clean_def) && println(io, "$(p)  <def>$(definition_markup(clean_def))</def>")
	end
	emit_citations(io, citations, level + 1)
	emit_children(io, children, level + 1, sense_id)
	println(io, "$(p)</sense>")
end

function emit_default_sense(io::IO, indent::Indent, level::Int, sense_id::String; extra_attrs::String = "")
	p = pad(level)
	content = markup_to_tei(indent.content)
	usg_els, clean_def = split_def_usg(content)
	println(io, "$(p)<sense$(id_attr(sense_id))$(extra_attrs)>")
	for el in usg_els
		println(io, "$(p)  $(el)")
	end
	!isempty(clean_def) && println(io, "$(p)  <def>$(definition_markup(clean_def))</def>")
	emit_citations(io, indent.citations, level + 1)
	emit_children(io, indent.children, level + 1, sense_id)
	println(io, "$(p)</sense>")
end

# ── Role-specific dispatch methods ───────────────────────────────

function emit_indent(io::IO, indent::Indent, ::Figurative, level::Int, sense_id::String)
	content = markup_to_tei(indent.content)
	label, def_text = split_label(content)
	emit_label_sense(io, label, "sem", def_text,
		indent.citations, indent.children, level;
		sense_id, extra_attrs = " type=\"figuré\"")
end

function emit_indent(io::IO, indent::Indent, ::DomainLabel, level::Int, sense_id::String)
	content = markup_to_tei(indent.content)
	label, def_text = split_label(content)
	if !isempty(label) && !isempty(def_text)
		emit_label_sense(io, label, "domain", def_text,
			indent.citations, indent.children, level; sense_id)
	else
		emit_default_sense(io, indent, level, sense_id)
	end
end

function emit_indent(io::IO, indent::Indent, ::RegisterLabel, level::Int, sense_id::String)
	content = markup_to_tei(indent.content)
	bare = split_bare_transition(content)
	label, def_text = bare !== nothing ? bare : split_label(content)
	emit_label_sense(io, label, "register", def_text,
		indent.citations, indent.children, level; sense_id)
end

function emit_indent(io::IO, indent::Indent, ::Locution, level::Int, sense_id::String)
	p = pad(level)
	content = markup_to_tei(indent.content)
	println(io, "$(p)<re type=\"locution\"$(id_attr(sense_id))>")
	if !isempty(indent.canonical_form)
		println(io, "$(p)  <form type=\"lemma\"><orth>$(escape_xml(indent.canonical_form))</orth></form>")
	end
	println(io, "$(p)  <def>$(definition_markup(content))</def>")
	emit_citations(io, indent.citations, level + 1)
	println(io, "$(p)</re>")
end

function emit_indent(io::IO, indent::Indent, ::Proverb, level::Int, sense_id::String)
	p = pad(level)
	content = markup_to_tei(indent.content)
	println(io, "$(p)<re type=\"proverbe\"$(id_attr(sense_id))>")
	println(io, "$(p)  <def>$(definition_markup(content))</def>")
	emit_citations(io, indent.citations, level + 1)
	println(io, "$(p)</re>")
end

function emit_indent(io::IO, indent::Indent, ::CrossReference, level::Int, sense_id::String)
	p = pad(level)
	content = markup_to_tei(indent.content)
	println(io, "$(p)<note type=\"xref\"$(id_attr(sense_id))>$(content)</note>")
end

function emit_indent(io::IO, indent::Indent, role::Union{NatureLabel, VoiceTransition}, level::Int, sense_id::String)
	content = markup_to_tei(indent.content)
	gs = split_gram(content)

	if !isempty(gs.label_text) && !(is_balanced(gs.pre_text) && is_balanced(gs.def_text))
		emit_default_sense(io, indent, level, sense_id)
		return
	end

	if isempty(gs.label_text)
		bare = split_bare_transition(content)
		label, def_text = bare !== nothing ? bare : split_label(content)
		if !isempty(indent.children) || !isempty(def_text) || !isempty(indent.citations)
			emit_label_sense(io, label, "gram", def_text,
				indent.citations, indent.children, level; sense_id)
		else
			for element in route_label_markup("gram", label)
				println(io, "$(pad(level))$(element)")
			end
		end
		return
	end

	has_body = !isempty(gs.def_text) || !isempty(indent.citations) || !isempty(indent.children)
	if !has_body && gs.pre_kind == :none
		for element in route_label_markup("gram", gs.label_text)
			println(io, "$(pad(level))$(element)")
		end
		return
	end

	p = pad(level)
	println(io, "$(p)<sense$(id_attr(sense_id))>")
	if gs.pre_kind in (:reflexive_form, :locution_form)
		println(io, "$(p)  <form type=\"lemma\"><orth>$(escape_xml(strip_tags(gs.pre_text)))</orth></form>")
	end
	for element in route_label_markup("gram", gs.label_text)
		println(io, "$(p)  $(element)")
	end
	if !isempty(gs.def_text)
		usg_els, clean_def = split_def_usg(gs.def_text)
		for el in usg_els
			println(io, "$(p)  $(el)")
		end
		!isempty(clean_def) && println(io, "$(p)  <def>$(definition_markup(clean_def))</def>")
	end
	emit_citations(io, indent.citations, level + 1)
	emit_children(io, indent.children, level + 1, sense_id)
	println(io, "$(p)</sense>")
end

function emit_indent(io::IO, indent::Indent, ::Unclassified, level::Int, sense_id::String)
	emit_default_sense(io, indent, level, sense_id; extra_attrs = " ana=\"unclassified\"")
end

# ── Body element emission ────────────────────────────────────────

function emit_body_element(io::IO, sense::Sense, level::Int, sense_id::String)
	p = pad(level)
	attrs = id_attr(sense_id)
	sense.num !== nothing && (attrs *= " n=\"$(sense.num)\"")
	sense.is_supplement && (attrs *= " source=\"supplement\"")

	println(io, "$(p)<sense$(attrs)>")

	if !isempty(sense.content)
		content = markup_to_tei(sense.content)
		usg_els, clean_def = split_def_usg(content)
		for el in usg_els
			println(io, "$(p)  $(el)")
		end
		!isempty(clean_def) && println(io, "$(p)  <def>$(definition_markup(clean_def))</def>")
	end

	emit_citations(io, sense.citations, level + 1)

	for (i, indent) in enumerate(sense.indents)
		child_id = isempty(sense_id) ? "" : "$(sense_id).$(i)"
		emit_indent(io, indent, level + 1, child_id)
	end

	for rub in sense.rubriques
		emit_rubrique(io, rub, level + 1)
	end

	println(io, "$(p)</sense>")
end

function emit_body_element(io::IO, group::TransitionGroup, level::Int, sense_id::String)
	p = pad(level)
	if group.kind == :strong
		println(io, "$(p)<entry$(id_attr(sense_id)) xml:lang=\"$(object_language)\" type=\"grammaticalVariant\">")
		println(io, "$(p)  <form type=\"lemma\"><orth>$(escape_xml(group.form))</orth></form>")
		println(io, "$(p)  $(pos_group_markup(group.pos))")
	else
		label = lowercase_text_nodes(markup_to_tei(group.transition_content))
		println(io, "$(p)<sense$(id_attr(sense_id))>")
		for element in route_label_markup("gram", label)
			println(io, "$(p)  $(element)")
		end
	end

	for (i, sub) in enumerate(group.sub_senses)
		sub_id = isempty(sense_id) ? "" : "$(sense_id).$(i)"
		emit_body_element(io, sub, level + 1, sub_id)
	end

	if group.kind == :strong
		println(io, "$(p)</entry>")
	else
		println(io, "$(p)</sense>")
	end
end

# ── Rubrique emission (dispatched on RubriqueKind) ───────────────

function emit_rubrique_body(io::IO, rub::Rubrique, level::Int)
	p = pad(level)
	!isempty(rub.content) && println(io, "$(p)  <p>$(markup_to_tei(rub.content))</p>")
	emit_citations(io, rub.citations, level + 1)
	for indent in rub.indents
		println(io, "$(p)  <p>$(markup_to_tei(indent.content))</p>")
		emit_citations(io, indent.citations, level + 1)
	end
end

const rubrique_wrappers = Dict{Type, Tuple{String, String}}(
	Historique => ("<note type=\"historique\">", "</note>"),
	Remarque => ("<note type=\"remarque\">", "</note>"),
	Supplement => ("<note type=\"supplément\">", "</note>"),
	Etymologie => ("<etym>", "</etym>"),
	Synonyme => ("<re type=\"synonyme\">", "</re>"),
	Proverbes => ("<re type=\"proverbes\">", "</re>"),
)

function emit_rubrique(io::IO, rub::Rubrique, level::Int)
	wrapper = get(rubrique_wrappers, typeof(rub.kind), nothing)
	wrapper === nothing && return
	p = pad(level)
	println(io, "$(p)$(wrapper[1])")
	emit_rubrique_body(io, rub, level)
	println(io, "$(p)$(wrapper[2])")
end

# ── Orthography and pronunciation ────────────────────────────────

function orth_markup(headword::AbstractString)::String
	printed = escape_xml(headword)
	"<orth norm=\"$(escape_xml(lowercase(headword)))\">$(printed)</orth>"
end

# Littré's <pron> is often prescriptive commentary rather than a transcription.
# The discriminator is deliberately conservative — an uncertain case keeps
# <pron> — and every relocation is written to the side-channel report, which is
# the pure-emitter analogue of W4's suspect-token channel. Flags 5.2% of 77,943.
const pronunciation_prose_markers =
	r"(?:prononc|\s(?:disent|dit|est|sont|on|il|qui|que|mais|selon|certains|toujours|jamais)\s|quelques|plupart|suivant|syllabe|lorsque|aujourd)"i

function is_pronunciation_prose(pronunciation::AbstractString)::Bool
	length(pronunciation) > 60 && return true
	occursin(r"\.\s", pronunciation) && return true
	occursin(';', pronunciation) && length(pronunciation) > 25 && return true
	occursin(pronunciation_prose_markers, pronunciation)
end

const pronunciation_report_path =
	joinpath(@__DIR__, "..", "test", "reports", "pron_prose_flags.tsv")

const pronunciation_flags = Tuple{String, String, String}[]

function record_pronunciation_flag(entry::Entry)
	push!(pronunciation_flags, (entry.id[], entry.headword, entry.pronunciation))
end

function write_pronunciation_report(path::AbstractString = pronunciation_report_path)
	mkpath(dirname(path))
	open(path, "w") do io
		println(io, "entry_id\theadword\tpronunciation")
		for (id, headword, pronunciation) in pronunciation_flags
			println(io, "$(id)\t$(headword)\t$(replace(pronunciation, '\t' => ' '))")
		end
	end
	@info "Wrote $(length(pronunciation_flags)) pronunciation relocations to $path"
end

# ── Entry emission ───────────────────────────────────────────────

function emit_entry(io::IO, entry::Entry, level::Int)
	p = pad(level)
	xml_id = escape_xml(entry.id[])
	attrs = "xml:id=\"$(xml_id)\" xml:lang=\"$(object_language)\" type=\"mainEntry\""
	entry.is_supplement && (attrs *= " source=\"supplement\"")

	println(io, "$(p)<entry $(attrs)>")

	println(io, "$(p)  <form type=\"lemma\">")
	println(io, "$(p)    $(orth_markup(entry.headword))")
	prose_pronunciation = !isempty(entry.pronunciation) && is_pronunciation_prose(entry.pronunciation)
	if !isempty(entry.pronunciation) && !prose_pronunciation
		println(io, "$(p)    <pron>$(escape_xml(entry.pronunciation))</pron>")
	end
	println(io, "$(p)  </form>")
	if prose_pronunciation
		println(io, "$(p)  <note type=\"pronunciation\">$(escape_xml(entry.pronunciation))</note>")
		record_pronunciation_flag(entry)
	end

	!isempty(entry.pos) && println(io, "$(p)  $(pos_group_markup(entry.pos))")

	for (i, el) in enumerate(entry.body)
		sense_id = "$(xml_id)_s$(i)"
		emit_body_element(io, el, level + 1, sense_id)
	end

	for rub in entry.rubriques
		emit_rubrique(io, rub, level + 1)
	end

	println(io, "$(p)</entry>")
end

# ── Top-level ────────────────────────────────────────────────────

const tei_header = """
<?xml version="1.0" encoding="UTF-8"?>
<TEI xmlns="http://www.tei-c.org/ns/1.0" xml:id="littre" type="lex-0">
<teiHeader>
  <fileDesc>
    <titleStmt>
      <title type="full">Dictionnaire de la langue française</title>
      <title type="abbr">Littré</title>
      <author>
        <persName><forename>Émile</forename><surname>Littré</surname></persName>
      </author>
      <editor role="digital">
        <persName><forename>François</forename><surname>Gannaz</surname></persName>
      </editor>
      <editor role="enrichment">
        <persName><forename>Michael</forename><surname>Myers</surname></persName>
      </editor>
    </titleStmt>
    <editionStmt>
      <edition>TEI Lex-0 edition</edition>
    </editionStmt>
    <publicationStmt>
      <publisher>
        <persName><forename>Michael</forename><surname>Myers</surname></persName>
      </publisher>
      <availability status="free">
        <licence target="https://creativecommons.org/licenses/by-sa/4.0/">CC BY-SA 4.0</licence>
      </availability>
    </publicationStmt>
    <sourceDesc>
      <listBibl type="dictionaries">
        <biblStruct xml:id="littre-print">
          <monogr>
            <author>
              <persName><forename>Émile</forename><surname>Littré</surname></persName>
            </author>
            <title level="m">Dictionnaire de la langue française</title>
            <imprint>
              <publisher>Hachette</publisher>
              <pubPlace>Paris</pubPlace>
              <date notBefore="1872" notAfter="1877">1872–1877</date>
            </imprint>
            <extent>
              <measure unit="volumes" quantity="4">4 volumes</measure>
            </extent>
          </monogr>
        </biblStruct>
        <biblStruct xml:id="xmlittre">
          <monogr corresp="https://bitbucket.org/Mytskine/xmlittre-data">
            <author>
              <persName><forename>François</forename><surname>Gannaz</surname></persName>
            </author>
            <title level="m">XMLittré</title>
            <edition>1.3</edition>
          </monogr>
        </biblStruct>
      </listBibl>
    </sourceDesc>
  </fileDesc>
  <profileDesc>
    <langUsage>
      <language ident="fr-x-lit19c" role="objectLanguage">
        <name xml:lang="en">19th-century literary French</name>
        <name xml:lang="fr">Français littéraire du XIXᵉ siècle</name>
        <date notBefore="1801" notAfter="1900"/>
      </language>
      <language ident="fr" role="workingLanguage">
        <name xml:lang="en">French</name>
        <name xml:lang="fr">Français</name>
      </language>
    </langUsage>
  </profileDesc>
  <revisionDesc>
    <change when="2026-07-19" n="0.2.0">TEI Lex-0 conformance branch: schema-valid corpus (RNG), entry-shell identity attributes, and header shell.</change>
  </revisionDesc>
</teiHeader>
<text>
<body>
"""

const tei_footer = """</body>
</text>
</TEI>
"""

function emit_tei(entries::Vector{Entry}, output_path::String)
	empty!(pronunciation_flags)
	open(output_path, "w") do io
		print(io, tei_header)
		for entry in entries
			emit_entry(io, entry, 1)
		end
		print(io, tei_footer)
	end
	write_pronunciation_report()
	@info "Wrote $(length(entries)) entries to $output_path"
end
