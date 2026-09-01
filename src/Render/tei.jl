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
	citations::Dict{RawSpan, String}
	rubrique_notes::Dict{RawSpan, String}
end

Names(entries, nodes, citations) = Names(entries, nodes, citations, Dict{RawSpan, String}())

function name_node!(
	names::Names, identifiers::Identifiers, node::Resolve.ResolvedNode,
	prefix::AbstractString, index::Int, nested::Bool,
)
	if node.node_type isa Adjudication.SubLemma || node.node_type isa Adjudication.VoiceVariant
		entry = mint!(identifiers, string(prefix, "_", slug(something(node.form, "")));
			normalize = false)
		inner = mint!(identifiers, sense_candidate(entry, 1, false); normalize = false)
		names.nodes[node.span] = NodeNames(entry, inner)
		position = 0
		for child in node.children
			positional = !(child.node_type isa Adjudication.SubLemma ||
				child.node_type isa Adjudication.VoiceVariant)
			positional && (position += 1)
			name_node!(names, identifiers, child, inner, position, true)
		end
	else
		sense = mint!(identifiers, sense_candidate(prefix, index, nested); normalize = false)
		names.nodes[node.span] = NodeNames(nothing, sense)
		position = 0
		for child in node.children
			positional = !(child.node_type isa Adjudication.SubLemma ||
				child.node_type isa Adjudication.VoiceVariant)
			positional && (position += 1)
			name_node!(names, identifiers, child, sense, position, true)
		end
	end
	nothing
end

# definition content that is nothing but punctuation; carried as `<pc>`
function punctuation_only(definition::Vector{Resolve.Inline})::Bool
	isempty(definition) && return false
	all(definition) do item
		item isa Resolve.TextRun || return false
		text = strip(item.text)
		!isempty(text) && all(character -> ispunct(character), text)
	end
end

function render_punctuation(io::IO, definition::Vector{Resolve.Inline})
	write(io, "<pc>")
	for item in definition
		write(io, escape_xml(strip(item.text)))
	end
	write(io, "</pc>")
	nothing
end

function assign_names(corpus::Resolve.ResolvedCorpus)::Names
	identifiers = Identifiers()
	names = Names(
		Dict{RawSpan, String}(), Dict{RawSpan, NodeNames}(), Dict{RawSpan, String}(),
		Dict{RawSpan, String}(),
	)
	for entry in corpus.entries
		name = mint!(identifiers, entry.headword)
		names.entries[entry.span] = name
		position = 0
		for node in entry.nodes
			position += 1
			name_node!(names, identifiers, node, name, position, false)
		end
		for rubrique in entry.rubriques
			for item in rubrique.items
				item isa Resolve.RubriqueNode || continue
				position += 1
				name_node!(names, identifiers, item.node, name, position, false)
			end
		end
		proverb_prose = [
			item for rubrique in entry.rubriques
			if Resolve.conventions_for(rubrique.name).note == "proverb"
			for item in rubrique.items if item isa Resolve.RubriqueProse
		]
		sort!(proverb_prose; by = item -> item.span.start_byte)
		for (note_position, prose) in enumerate(proverb_prose)
			names.rubrique_notes[prose.span] = mint!(
				identifiers, string(name, "_proverb_", note_position); normalize = false,
			)
		end
		citations = Resolve.all_entry_citations(entry)
		sort!(citations; by = citation -> citation.span.start_byte)
		for (citation_position, citation) in enumerate(citations)
			names.citations[citation.span] = mint!(
				identifiers, string(name, "_c", citation_position); normalize = false,
			)
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
			if item.source_element == "exemple"
				write(io, "<seg type=\"example\"$(language)>$(escape_xml(item.text))</seg>")
			else
				write(io, "<hi rend=\"italic\"$(language)>$(escape_xml(item.text))</hi>")
			end
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

function same_grammatical_marker(
	left::Resolve.Qualification, right::Resolve.Qualification,
)::Bool
	left.marker_printed == right.marker_printed &&
	left.span.file == right.span.file &&
	left.span.start_byte == right.span.start_byte &&
	left.span.end_byte == right.span.end_byte
end

function render_grammatical_marker(io::IO, qualifications::Vector{Resolve.Qualification})
	marker = first(qualifications).marker_printed
	positions = UnitRange{Int}[]
	cursor = firstindex(marker)
	for qualification in qualifications
		position = findnext(qualification.printed, marker, cursor)
		if position === nothing
			for (index, fallback) in enumerate(qualifications)
				index > 1 && write(io, " ")
				render_qualification(io, fallback)
			end
			return nothing
		end
		push!(positions, position)
		cursor = nextind(marker, last(position))
	end

	cursor = firstindex(marker)
	for (qualification, position) in zip(qualifications, positions)
		if cursor < first(position)
			write(io, escape_xml(marker[cursor:prevind(marker, first(position))]))
		end
		render_qualification(io, qualification)
		cursor = nextind(marker, last(position))
	end
	if !isempty(marker) && cursor <= lastindex(marker)
		write(io, escape_xml(marker[cursor:lastindex(marker)]))
	end
	nothing
end

function render_grammar(io::IO, qualifications::Vector{Resolve.Qualification})
	grammatical = filter(item -> item.channel == :gram, qualifications)
	isempty(grammatical) && return nothing
	write(io, "<gramGrp>")
	start = 1
	while start <= length(grammatical)
		stop = start
		while stop < length(grammatical) &&
				same_grammatical_marker(grammatical[start], grammatical[stop + 1])
			stop += 1
		end
		render_grammatical_marker(io, grammatical[start:stop])
		start = stop + 1
	end
	write(io, "</gramGrp>")
	nothing
end

function render_citation(
	io::IO, citation::Resolve.Citation, names::Names; subtype::AbstractString = "", depth::Int = 0,
	date_text::AbstractString = "", not_before = nothing, not_after = nothing,
	corresp::Union{Nothing, String} = nothing,
)
	subtype_attribute = isempty(subtype) ? "" : " subtype=\"$(escape_attribute(subtype))\""
	corresp_attribute = corresp === nothing ? "" : " corresp=\"#$(escape_attribute(corresp))\""
	citation_id = names.citations[citation.span]
	write(io, "<cit type=\"example\" xml:id=\"", citation_id, "\"",
		subtype_attribute, corresp_attribute, ">")
	newline(io, depth + 1)
	write(io, "<quote>")
	render_inline(io, citation.quotation, names)
	write(io, "</quote>")
	dated = not_before !== nothing && not_after !== nothing
	if dated || !isempty(citation.resolved_author) || !isempty(citation.author) ||
			!isempty(citation.reference)
		newline(io, depth + 1)
		write(io, "<bibl>")
		if !isempty(citation.author)
			newline(io, depth + 2)
			corresp = citation.author_antecedent === nothing ? "" :
				" corresp=\"#$(names.citations[citation.author_antecedent])\""
			write(io, "<author", corresp, ">", escape_xml(citation.author), "</author>")
		end
		if !isempty(citation.reference)
			newline(io, depth + 2)
			corresp = citation.reference_antecedent === nothing ? "" :
				" corresp=\"#$(names.citations[citation.reference_antecedent])\""
			write(io, "<biblScope", corresp, ">", escape_xml(citation.reference), "</biblScope>")
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
function render_node(
	io::IO, node::Resolve.ResolvedNode, names::Names, depth::Int,
	rubriques::Vector{Resolve.ResolvedRubrique} = Resolve.ResolvedRubrique[],
	citation_subtype::AbstractString = "",
)
	if node.node_type isa Adjudication.SubLemma
		render_nested_entry(io, node, names, "relatedEntry", depth, citation_subtype)
		return nothing
	elseif node.node_type isa Adjudication.VoiceVariant
		# A form-bearing pronominal alternant is entry-like: Littré effectively opens a subsidiary
		# entry under the verb, so it serializes as a homonymic entry rather than a sense.
		render_nested_entry(io, node, names, "homonymicEntry", depth, citation_subtype)
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
		if punctuation_only(node.definition)
			render_punctuation(io, node.definition)
		else
			write(io, "<def>")
			render_inline(io, node.definition, names)
			write(io, "</def>")
		end
	end
	for citation in node.citations
		newline(io, depth + 1)
		render_citation(io, citation, names; subtype = citation_subtype, depth = depth + 1)
	end
	for child in node.children
		newline(io, depth + 1)
		render_node(io, child, names, depth + 1, rubriques, citation_subtype)
	end
	for rubrique in rubriques_under(rubriques, node.node_id)
		renderable(rubrique, rubriques) || continue
		newline(io, depth + 1)
		render_rubrique(io, rubrique, names, depth + 1, rubriques)
	end
	newline(io, depth)
	write(io, "</sense>")
	nothing
end

function render_nested_entry(
	io::IO, node::Resolve.ResolvedNode, names::Names, entry_type::AbstractString, depth::Int,
	citation_subtype::AbstractString = "",
)
	name = something(names.nodes[node.span].entry, "")
	write(io, "<entry xml:id=\"", name, "\" xml:lang=\"", object_language,
		"\" type=\"", entry_type, "\">")
	for (index, form) in enumerate(node.forms)
		newline(io, depth + 1)
		form_type = index == 1 ? "lemma" : "variant"
		write(io, "<form type=\"", form_type, "\"><orth")
		if form.value === nothing
			write(io, ">", escape_xml(form.printed), "</orth></form>")
		else
			write(io, " value=\"", escape_attribute(form.value), "\"/></form>")
		end
	end
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
		if punctuation_only(node.definition)
			render_punctuation(io, node.definition)
		else
			write(io, "<def>")
			render_inline(io, node.definition, names)
			write(io, "</def>")
		end
	end
	for citation in node.citations
		newline(io, depth + 2)
		render_citation(io, citation, names; subtype = citation_subtype, depth = depth + 2)
	end
	for child in node.children
		newline(io, depth + 2)
		render_node(io, child, names, depth + 2, Resolve.ResolvedRubrique[], citation_subtype)
	end
	newline(io, depth + 1)
	write(io, "</sense>")
	newline(io, depth)
	write(io, "</entry>")
	nothing
end

function render_etym_forms(io::IO, forms::Vector{String}, italic::Bool)
	form_type = length(forms) > 1 ? " type=\"variant\"" : ""
	rend = italic ? " rend=\"italic\"" : ""
	for form in forms
		write(io, "<form", form_type, "><orth", rend, ">", escape_xml(form), "</orth></form>")
	end
	nothing
end

function render_etym_segment(io::IO, cit::Resolve.EtymCit, ::Names)
	language = isempty(cit.language) ? "" : " xml:lang=\"$(escape_attribute(cit.language))\""
	write(io, "<cit type=\"", String(cit.cit_type), "\"", language, ">")
	if cit.cue !== nothing
		expand = isempty(cit.cue.expand) ? "" : " expand=\"$(escape_attribute(cit.cue.expand))\""
		write(io, "<lang", expand, " norm=\"", escape_attribute(cit.cue.code), "\">",
			escape_xml(cit.cue.printed), "</lang>")
		isempty(cit.cue.trailing) ||
			write(io, "<pc>", escape_xml(cit.cue.trailing), "</pc>")
	end
	# Littré's reconstruction marker has no Lex-0 element of its own; the established fallback is
	# a usage hint rather than an invented attribute.
	cit.fictif && write(io, "<usg type=\"hint\">fictif</usg>")
	render_etym_forms(io, cit.forms, cit.italic)
	isempty(cit.gloss) || write(io, "<gloss>", escape_xml(cit.gloss), "</gloss>")
	write(io, "</cit>")
	nothing
end


function render_etym_segment(io::IO, component::Resolve.EtymComponent, ::Names)
	language = isempty(component.language) ? "fr" : component.language
	write(io, "<cit type=\"etymon\" xml:lang=\"", escape_attribute(language), "\">")
	render_etym_forms(io, component.forms, component.italic)
	write(io, "</cit>")
	nothing
end

function render_etym_segment(io::IO, literal::Resolve.EtymLiteral, ::Names)
	if literal.printed == ";" || literal.printed == ":"
		write(io, " <pc>", escape_xml(literal.printed), "</pc> ")
	elseif literal.printed == ","
		write(io, "<pc>,</pc> ")
	elseif literal.printed == "."
		write(io, "<pc>.</pc>")
	else
		write(io, "<pc>", escape_xml(literal.printed), "</pc>")
	end
	nothing
end

render_etym_segment(io::IO, connector::Resolve.EtymConnector, ::Names) =
	write(io, " ", escape_xml(connector.printed), " ")

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
rubriques_under_rubrique(
	rubriques::Vector{Resolve.ResolvedRubrique}, parent::Resolve.ResolvedRubrique,
) = filter(rubrique -> rubrique.parent_id == anchor_id(parent.span), rubriques)

rubrique_part_span(item::Resolve.RubriqueItem) = Resolve.rubrique_item_span(item)
rubrique_part_span(rubrique::Resolve.ResolvedRubrique) = rubrique.span
rubrique_part_span(group::Vector{Resolve.AnchoredEtymSegment}) = first(group).container_span

function etymology_groups(
	etymology::Vector{Resolve.AnchoredEtymSegment},
)::Vector{Vector{Resolve.AnchoredEtymSegment}}
	groups = Vector{Resolve.AnchoredEtymSegment}[]
	for anchored in etymology
		if isempty(groups) || first(last(groups)).container_span != anchored.container_span
			push!(groups, Resolve.AnchoredEtymSegment[])
		end
		push!(last(groups), anchored)
	end
	groups
end

function render_rubrique(
	io::IO, rubrique::Resolve.ResolvedRubrique, names::Names, depth::Int,
	rubriques::Vector{Resolve.ResolvedRubrique} = Resolve.ResolvedRubrique[],
)
	started = false
	function next_item!()
		if started
			newline(io, depth)
		else
			started = true
		end
		nothing
	end
	conventions = Resolve.conventions_for(rubrique.name)
	proverb_note_id = nothing
	heading = Resolve.rubrique_heading(rubrique.name)
	parts = Any[]
	append!(parts, etymology_groups(rubrique.etymology))
	append!(parts, rubrique.items)
	append!(parts, rubriques_under_rubrique(rubriques, rubrique))
	sort!(parts; by = part -> rubrique_part_span(part).start_byte)
	combine_heading = heading !== nothing && conventions.note == "proverb" &&
		!isempty(parts) && first(parts) isa Resolve.RubriqueProse
	if heading !== nothing && !combine_heading
		next_item!()
		write(io, "<note type=\"", escape_attribute(conventions.note),
			"\" subtype=\"label\">", escape_xml(heading), "</note>")
	end
	proverb_heading = combine_heading ? heading : nothing
	for part in parts
		if part isa Vector{Resolve.AnchoredEtymSegment}
			next_item!()
			write(io, "<etym>")
			for anchored in part
				render_etym_segment(io, anchored.segment, names)
			end
			write(io, "</etym>")
		elseif part isa Resolve.ResolvedRubrique
			next_item!()
			render_rubrique(io, part, names, depth, rubriques)
		elseif part isa Resolve.RubriqueProse
			next_item!()
			render_rubrique_item(
				io, part, names, conventions.note, conventions.subtype, depth;
				heading = proverb_heading,
			)
			if conventions.note == "proverb"
				proverb_note_id = names.rubrique_notes[part.span]
				proverb_heading = nothing
			end
		elseif part isa Resolve.RubriqueCitation && conventions.note == "proverb"
			next_item!()
			render_rubrique_item(
				io, part, names, conventions.note, conventions.subtype, depth;
				corresp = proverb_note_id,
			)
		else
			next_item!()
			render_rubrique_item(io, part, names, conventions.note, conventions.subtype, depth)
		end
	end
	nothing
end

render_rubrique_item(
	io::IO, label::Resolve.RubriqueLabel, ::Names, ::AbstractString, ::AbstractString, ::Int,
) = write(io, "<lbl type=\"", escape_attribute(label.kind), "\">", escape_xml(label.text), "</lbl>")

function render_rubrique_item(
	io::IO, citation::Resolve.RubriqueCitation, names::Names, ::AbstractString, ::AbstractString,
	depth::Int; corresp::Union{Nothing, String} = nothing,
)
	render_citation(
		io, citation.citation, names;
		subtype = citation.subtype, depth = depth, date_text = citation.date_text,
		not_before = citation.not_before, not_after = citation.not_after, corresp,
	)
end

function render_rubrique_item(
	io::IO, prose::Resolve.RubriqueProse, names::Names, note_type::AbstractString,
	::AbstractString, ::Int; heading::Union{Nothing, String} = nothing,
)
	note_id = note_type == "proverb" ? names.rubrique_notes[prose.span] : nothing
	id_attribute = note_id === nothing ? "" : " xml:id=\"$(escape_attribute(note_id))\""
	write(io, "<note type=\"", escape_attribute(note_type), "\"", id_attribute, ">")
	if note_type == "proverb"
		heading === nothing ||
			write(io, "<seg type=\"label\">", escape_xml(heading), "</seg> ")
		render_inline(io, prose.content, names; wrap_cross_reference = false)
	else
		write(io, "<seg>")
		render_inline(io, prose.content, names; wrap_cross_reference = false)
		write(io, "</seg>")
	end
	write(io, "</note>")
	nothing
end

function render_rubrique_item(
	io::IO, item::Resolve.RubriqueNode, names::Names, ::AbstractString,
	citation_subtype::AbstractString, depth::Int,
)
	render_node(io, item.node, names, depth, Resolve.ResolvedRubrique[], citation_subtype)
	nothing
end

"""
	rubriques_under(rubriques, node_id)

The rubriques the source placed inside a given block. Littré writes PROVERBE inside the very sense
it illustrates; emitting every rubrique at entry level would keep the material but lose which sense
it belonged to. A rubrique whose parent is the entry, or another rubrique, is not claimed here.
"""
rubriques_under(rubriques::Vector{Resolve.ResolvedRubrique}, node_id::AbstractString) =
	filter(rubrique -> rubrique.parent_id == node_id, rubriques)

function flatten_nodes(nodes::Vector{Resolve.ResolvedNode})::Vector{Resolve.ResolvedNode}
	flattened = Resolve.ResolvedNode[]
	visit(current) = for node in current
		push!(flattened, node)
		visit(node.children)
	end
	visit(nodes)
	flattened
end

renderable(rubrique::Resolve.ResolvedRubrique) =
	!(isempty(rubrique.items) && isempty(rubrique.etymology))

function renderable(
	rubrique::Resolve.ResolvedRubrique, rubriques::Vector{Resolve.ResolvedRubrique},
)::Bool
	renderable(rubrique) || any(
		child -> renderable(child, rubriques),
		rubriques_under_rubrique(rubriques, rubrique),
	)
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
		render_node(io, node, names, depth + 1, entry.rubriques)
	end
	# Source order: Littré puts HISTORIQUE before ÉTYMOLOGIE in some entries and after in others,
	# and entry content is unordered under Lex-0, so nothing is gained by imposing a house order.
	claimed = Set(rubrique.span for node in flatten_nodes(entry.nodes)
		for rubrique in rubriques_under(entry.rubriques, node.node_id))
	rubrique_ids = Set(anchor_id(rubrique.span) for rubrique in entry.rubriques)
	nested = Set(
		rubrique.span for rubrique in entry.rubriques
		if rubrique.parent_id !== nothing && rubrique.parent_id in rubrique_ids
	)
	for rubrique in sort(entry.rubriques; by = rubrique -> rubrique.span.start_byte)
		renderable(rubrique, entry.rubriques) || continue
		rubrique.span in claimed && continue
		rubrique.span in nested && continue
		newline(io, depth + 1)
		render_rubrique(io, rubrique, names, depth + 1, entry.rubriques)
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
