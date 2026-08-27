const object_language = "fr-x-lit19c"
const indent_width = 2

function escape_xml(text::AbstractString)::String
	replace(text, '&' => "&amp;", '<' => "&lt;", '>' => "&gt;")
end

escape_attribute(text::AbstractString)::String = replace(escape_xml(text), '"' => "&quot;")

function indent(io::IO, depth::Int)
	write(io, repeat(" ", indent_width * depth))
	nothing
end

function newline(io::IO, depth::Int)
	write(io, '\n')
	indent(io, depth)
	nothing
end

function slug(text::AbstractString)::String
	folded = Unicode.normalize(lowercase(text); stripmark = true)
	trimmed = strip(replace(folded, r"[^a-z0-9]+" => "_"), '_')
	isempty(trimmed) ? "x" : trimmed
end

mutable struct Identifiers
	used::Set{String}
end

Identifiers() = Identifiers(Set{String}())

# `normalize = false` for names already composed from safe parts: slugging again would flatten the
# dots that carry a sense's position within its parent.
function mint!(identifiers::Identifiers, candidate::AbstractString; normalize::Bool = true)::String
	base = normalize ? slug(candidate) : candidate
	name = base
	counter = 1
	while name in identifiers.used
		counter += 1
		name = "$(base)_$(counter)"
	end
	push!(identifiers.used, name)
	name
end

"""
	sense_candidate(prefix, index, nested)

Positional, not a collision counter: `angoisse_s3` is the entry's third sense and `angoisse_s3.2`
the second sense inside it. `mint!` still guards genuine collisions, since homographs normalize to
the same headword slug, but no longer supplies the ordinal.
"""
sense_candidate(prefix::AbstractString, index::Int, nested::Bool)::String =
	nested ? string(prefix, '.', index) : string(prefix, "_s", index)

"""
	assign_names(corpus)

Every `xml:id` the document will carry, minted in render order and keyed by raw anchor. A
cross-reference can only be pointed at a target whose identifier is already known, so naming
happens in its own pass and the render walk does no minting at all.

A form-bearing node needs two names: one for its nested `<entry>` and one for the `<sense>` inside
it. Both are recorded, and a reference to that node resolves to the entry.
"""
struct NodeNames
	entry::Union{Nothing, String}
	sense::String
end

struct Names
	entries::Dict{RawSpan, String}
	nodes::Dict{RawSpan, NodeNames}
end

function name_node!(
	names::Names, identifiers::Identifiers, node::Resolve.ResolvedNode,
	prefix::AbstractString, index::Int, nested::Bool,
)
	if node.node_type isa Adjudication.SubLemma || node.node_type isa Adjudication.VoiceVariant
		entry = mint!(identifiers, string(prefix, "_", slug(something(node.form, "")));
			normalize = false)
		inner = mint!(identifiers, sense_candidate(entry, 1, false); normalize = false)
		names.nodes[node.span] = NodeNames(entry, inner)
		for (position, child) in enumerate(node.children)
			name_node!(names, identifiers, child, inner, position, true)
		end
	else
		sense = mint!(identifiers, sense_candidate(prefix, index, nested); normalize = false)
		names.nodes[node.span] = NodeNames(nothing, sense)
		for (position, child) in enumerate(node.children)
			name_node!(names, identifiers, child, sense, position, true)
		end
	end
	nothing
end

function assign_names(corpus::Resolve.ResolvedCorpus)::Names
	identifiers = Identifiers()
	names = Names(Dict{RawSpan, String}(), Dict{RawSpan, NodeNames}())
	for entry in corpus.entries
		name = mint!(identifiers, entry.headword)
		names.entries[entry.span] = name
		for (position, node) in enumerate(entry.nodes)
			name_node!(names, identifiers, node, name, position, false)
		end
	end
	names
end

"""
	target_name(names, resolved)

The identifier a resolved cross-reference points at, or `nothing`. The compliance contract admits
an internal `target="#xml-id"` only where the target is reliably resolved, and prefers a textual
reference to a guessed pointer, so an unresolved reference emits `<ref>` without `@target`.
"""
function target_name(names::Names, resolved::Union{Nothing, RawSpan})::Union{Nothing, String}
	resolved === nothing && return nothing
	haskey(names.entries, resolved) && return names.entries[resolved]
	haskey(names.nodes, resolved) || return nothing
	node = names.nodes[resolved]
	node.entry === nothing ? node.sense : node.entry
end

# `<def>` and `<quote>` admit `<xr>`; `<seg>` admits only the bare `<ref>`.
function render_inline(
	io::IO, items::Vector{Resolve.Inline}, names::Names; wrap_cross_reference::Bool = true,
)
	for item in items
		if item isa Resolve.CrossReference
			name = target_name(names, item.resolved)
			target = name === nothing ? "" : " target=\"#$(escape_attribute(name))\""
			reference = string(
				"<ref type=\"entry\"", target, ">", escape_xml(item.text), "</ref>",
			)
			write(io, wrap_cross_reference ? "<xr type=\"related\">" * reference * "</xr>" : reference)
		elseif item isa Resolve.Emphasis
			language = item.language === nothing || isempty(item.language) ? "" :
				" xml:lang=\"$(escape_attribute(item.language))\""
			write(io, "<hi rend=\"italic\"", language, ">", escape_xml(item.text), "</hi>")
		else
			write(io, escape_xml(item.text))
		end
	end
	nothing
end

function render_qualification(io::IO, qualification::Resolve.Qualification)
	norm = isempty(qualification.norm) ? "" : " norm=\"$(escape_attribute(qualification.norm))\""
	element = qualification.channel == :usg ? "usg" : "gram"
	write(io, "<", element, " type=\"", escape_attribute(qualification.type), "\"", norm, ">",
		escape_xml(qualification.printed), "</", element, ">")
	nothing
end

function render_grammar(io::IO, qualifications::Vector{Resolve.Qualification})
	grammatical = filter(item -> item.channel == :gram, qualifications)
	isempty(grammatical) && return nothing
	write(io, "<gramGrp>")
	foreach(item -> render_qualification(io, item), grammatical)
	write(io, "</gramGrp>")
	nothing
end

function render_citation(
	io::IO, citation::Resolve.Citation, names::Names; subtype::AbstractString = "", depth::Int = 0,
	date_text::AbstractString = "", not_before = nothing, not_after = nothing,
)
	attribute = isempty(subtype) ? "" : " subtype=\"$(escape_attribute(subtype))\""
	write(io, "<cit type=\"example\"", attribute, ">")
	newline(io, depth + 1)
	write(io, "<quote>")
	render_inline(io, citation.quotation, names)
	write(io, "</quote>")
	dated = not_before !== nothing && not_after !== nothing
	if dated || !isempty(citation.resolved_author) || !isempty(citation.author) ||
			!isempty(citation.reference)
		newline(io, depth + 1)
		write(io, "<bibl>")
		# A resolved name was not printed at this citation, so the resolution is marked rather than
		# passed off as source text. An unresolved ID. keeps what Littré printed.
		if citation.resolution == :resolved
			newline(io, depth + 2)
			write(io, "<author ana=\"resolved\">", escape_xml(citation.resolved_author), "</author>")
		elseif !isempty(citation.author)
			newline(io, depth + 2)
			write(io, "<author>", escape_xml(citation.author), "</author>")
		end
		if !isempty(citation.reference)
			newline(io, depth + 2)
			write(io, "<biblScope>", escape_xml(citation.reference), "</biblScope>")
		end
		# Littré prints the century once over a group of attestations. Duplicating the range into
		# each bibl is what makes the corpus queryable by date rather than only by header text.
		if dated
			newline(io, depth + 2)
			# xsd:gYear, so a tenth-century range is 0901 rather than 901.
			write(io, "<date notBefore=\"", lpad(not_before, 4, '0'),
				"\" notAfter=\"", lpad(not_after, 4, '0'), "\">",
				escape_xml(date_text), "</date>")
		end
		newline(io, depth + 1)
		write(io, "</bibl>")
	end
	newline(io, depth)
	write(io, "</cit>")
	nothing
end

"""
	render_node(io, node, names, depth)

A node with an underdetermined type is serialized as `<sense><def>…</def></sense>` without
implying that an adjudicator positively established an ordinary sense. A positively asserted
`SubLemma` becomes a nested `<entry type="relatedEntry">`, which is what lets a sub-lemma sit
inside the sense that contains it.
"""
function render_node(io::IO, node::Resolve.ResolvedNode, names::Names, depth::Int)
	if node.node_type isa Adjudication.SubLemma
		render_nested_entry(io, node, names, "relatedEntry", depth)
		return nothing
	elseif node.node_type isa Adjudication.VoiceVariant
		# A form-bearing pronominal alternant is entry-like: Littré effectively opens a subsidiary
		# entry under the verb, so it serializes as a homonymic entry rather than a sense.
		render_nested_entry(io, node, names, "homonymicEntry", depth)
		return nothing
	end
	name = names.nodes[node.span].sense
	number = node.number === nothing ? "" : " n=\"$(escape_attribute(node.number))\""
	write(io, "<sense xml:id=\"", name, "\"", number, ">")
	for qualification in node.qualifications
		qualification.channel == :usg || continue
		newline(io, depth + 1)
		render_qualification(io, qualification)
	end
	if any(item -> item.channel == :gram, node.qualifications)
		newline(io, depth + 1)
		render_grammar(io, node.qualifications)
	end
	if !isempty(node.definition)
		newline(io, depth + 1)
		write(io, "<def>")
		render_inline(io, node.definition, names)
		write(io, "</def>")
	end
	for citation in node.citations
		newline(io, depth + 1)
		render_citation(io, citation, names; depth = depth + 1)
	end
	for child in node.children
		newline(io, depth + 1)
		render_node(io, child, names, depth + 1)
	end
	newline(io, depth)
	write(io, "</sense>")
	nothing
end

function render_nested_entry(
	io::IO, node::Resolve.ResolvedNode, names::Names, entry_type::AbstractString, depth::Int,
)
	form = something(node.form, "")
	name = something(names.nodes[node.span].entry, "")
	write(io, "<entry xml:id=\"", name, "\" xml:lang=\"", object_language,
		"\" type=\"", entry_type, "\">")
	newline(io, depth + 1)
	write(io, "<form type=\"lemma\"><orth>", escape_xml(form), "</orth></form>")
	if any(item -> item.channel == :gram, node.qualifications)
		newline(io, depth + 1)
		render_grammar(io, node.qualifications)
	end
	# The punctuation Littré prints between a form and its gloss belongs to neither span, so it
	# is carried as <pc> rather than silently dropped or glued onto the gloss.
	if node.separator !== nothing
		newline(io, depth + 1)
		write(io, "<pc>", escape_xml(node.separator), "</pc>")
	end
	newline(io, depth + 1)
	inner = names.nodes[node.span].sense
	write(io, "<sense xml:id=\"", inner, "\">")
	for qualification in node.qualifications
		qualification.channel == :usg || continue
		newline(io, depth + 2)
		render_qualification(io, qualification)
	end
	if !isempty(node.definition)
		newline(io, depth + 2)
		write(io, "<def>")
		render_inline(io, node.definition, names)
		write(io, "</def>")
	end
	for citation in node.citations
		newline(io, depth + 2)
		render_citation(io, citation, names; depth = depth + 2)
	end
	for child in node.children
		newline(io, depth + 2)
		render_node(io, child, names, depth + 2)
	end
	newline(io, depth + 1)
	write(io, "</sense>")
	newline(io, depth)
	write(io, "</entry>")
	nothing
end

function render_etym_segment(io::IO, cit::Resolve.EtymCit, ::Names)
	language = isempty(cit.language) ? "" : " xml:lang=\"$(escape_attribute(cit.language))\""
	write(io, "<cit type=\"", String(cit.cit_type), "\"", language, ">")
	if cit.cue !== nothing
		expand = isempty(cit.cue.expand) ? "" : " expand=\"$(escape_attribute(cit.cue.expand))\""
		write(io, "<lang", expand, " norm=\"", escape_attribute(cit.cue.code), "\">",
			escape_xml(cit.cue.printed), "</lang>")
	end
	# Littré's reconstruction marker has no Lex-0 element of its own; the established fallback is
	# a usage hint rather than an invented attribute.
	cit.fictif && write(io, "<usg type=\"hint\">fictif</usg>")
	form_type = length(cit.forms) > 1 ? " type=\"variant\"" : ""
	for form in cit.forms
		write(io, "<form", form_type, "><orth>", escape_xml(form), "</orth></form>")
	end
	isempty(cit.gloss) || write(io, "<gloss>", escape_xml(cit.gloss), "</gloss>")
	write(io, "</cit>")
	nothing
end

render_etym_segment(io::IO, connector::Resolve.EtymConnector, ::Names) =
	write(io, "<lbl>", escape_xml(connector.printed), "</lbl>")

# The token is preserved rather than silently corrected; the epistemic claim rides on @ana.
render_etym_segment(io::IO, suspect::Resolve.EtymSuspect, ::Names) =
	write(io, "<lbl ana=\"suspect\">", escape_xml(suspect.token), "</lbl>")

render_etym_segment(io::IO, prose::Resolve.EtymProse, ::Names) =
	write(io, "<seg>", escape_xml(prose.text), "</seg>")

function render_etym_segment(io::IO, reference::Resolve.EtymCrossReference, names::Names)
	isempty(reference.label) ||
		write(io, "<lbl>", escape_xml(reference.label), "</lbl>")
	name = target_name(names, reference.resolved)
	target = name === nothing ? "" : " target=\"#$(escape_attribute(name))\""
	write(io, "<ref type=\"entry\"", target, ">", escape_xml(reference.printed), "</ref>")
	nothing
end

"""
	render_rubrique(io, rubrique, names, depth)

`<note>` cannot hold `<cit>` under Lex-0, so a rubrique's citations are lifted to entry level while
its prose stays in a note. Items are emitted in source order, which keeps a century label adjacent
to the attestations it introduces. The rubrique boundary is therefore not expressed in TEI; the
`subtype` and the rubrique's raw anchor in SQLite carry that association instead.
"""
function render_rubrique(io::IO, rubrique::Resolve.ResolvedRubrique, names::Names, depth::Int)
	started = false
	function next_item!()
		if started
			newline(io, depth)
		else
			started = true
		end
		nothing
	end
	if !isempty(rubrique.etymology)
		next_item!()
		write(io, "<etym>")
		for anchored in rubrique.etymology
			newline(io, depth + 1)
			render_etym_segment(io, anchored.segment, names)
		end
		newline(io, depth)
		write(io, "</etym>")
	end
	note_type = Resolve.conventions_for(rubrique.name).note
	for item in rubrique.items
		next_item!()
		render_rubrique_item(io, item, names, note_type, depth)
	end
	nothing
end

render_rubrique_item(io::IO, label::Resolve.RubriqueLabel, ::Names, ::AbstractString, ::Int) =
	write(io, "<lbl type=\"", escape_attribute(label.kind), "\">", escape_xml(label.text), "</lbl>")

render_rubrique_item(
	io::IO, citation::Resolve.RubriqueCitation, names::Names, ::AbstractString, depth::Int,
) =
	render_citation(
		io, citation.citation, names;
		subtype = citation.subtype, depth = depth, date_text = citation.date_text,
		not_before = citation.not_before, not_after = citation.not_after,
	)

function render_rubrique_item(
	io::IO, prose::Resolve.RubriqueProse, names::Names, note_type::AbstractString, ::Int,
)
	write(io, "<note type=\"", escape_attribute(note_type), "\"><seg>")
	render_inline(io, prose.content, names; wrap_cross_reference = false)
	write(io, "</seg></note>")
	nothing
end

function render_entry(io::IO, entry::Resolve.ResolvedEntry, names::Names, depth::Int)
	name = names.entries[entry.span]
	write(io, "<entry xml:id=\"", name, "\" xml:lang=\"", object_language, "\" type=\"mainEntry\">")
	newline(io, depth + 1)
	write(io, "<form type=\"lemma\"><orth>", escape_xml(entry.headword), "</orth>")
	entry.pronunciation === nothing ||
		write(io, "<pron>", escape_xml(entry.pronunciation), "</pron>")
	write(io, "</form>")
	if any(item -> item.channel == :gram, entry.grammar)
		newline(io, depth + 1)
		render_grammar(io, entry.grammar)
	end
	for qualification in entry.grammar
		qualification.channel == :usg || continue
		newline(io, depth + 1)
		render_qualification(io, qualification)
	end
	for node in entry.nodes
		newline(io, depth + 1)
		render_node(io, node, names, depth + 1)
	end
	# Source order: Littré puts HISTORIQUE before ÉTYMOLOGIE in some entries and after in others,
	# and entry content is unordered under Lex-0, so nothing is gained by imposing a house order.
	for rubrique in entry.rubriques
		isempty(rubrique.items) && isempty(rubrique.etymology) && continue
		newline(io, depth + 1)
		render_rubrique(io, rubrique, names, depth + 1)
	end
	newline(io, depth)
	write(io, "</entry>\n")
	nothing
end

function render_tei(
	corpus::Resolve.ResolvedCorpus, path::AbstractString; header::AbstractString = tei_header(),
)
	names = assign_names(corpus)
	open(path, "w") do handle
		write(handle, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
		write(handle, "<TEI xmlns=\"http://www.tei-c.org/ns/1.0\" xml:id=\"littre\" type=\"lex-0\">\n")
		write(handle, header)
		write(handle, "\n  <text>\n    <body>\n")
		for entry in corpus.entries
			indent(handle, 3)
			render_entry(handle, entry, names, 3)
		end
		write(handle, "    </body>\n  </text>\n</TEI>\n")
	end
	path
end

function tei_header()::String
	path = joinpath(normpath(joinpath(@__DIR__, "..", "..")), "data", "tei_header.xml")
	isfile(path) || error("missing TEI header at $(path)")
	strip(read(path, String))
end
