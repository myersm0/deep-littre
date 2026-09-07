const object_language = "fr-x-lit19c"
const indent_width = 2

escape_xml(text::AbstractString) =
	replace(text, '&' => "&amp;", '<' => "&lt;", '>' => "&gt;")

escape_attribute(text::AbstractString) =
	replace(escape_xml(text), '"' => "&quot;")

optional_attribute(name::AbstractString, ::Nothing) = ""

optional_attribute(name::AbstractString, value::AbstractString) =
	isempty(value) ? "" : " $(name)=\"$(escape_attribute(value))\""

optional_reference(name::AbstractString, ::Nothing) = ""

optional_reference(name::AbstractString, value::AbstractString) =
	isempty(value) ? "" : " $(name)=\"#$(escape_attribute(value))\""

function indent(io::IO, depth::Int)
	write(io, repeat(" ", indent_width * depth))
	return nothing
end

function newline(io::IO, depth::Int)
	write(io, '\n')
	indent(io, depth)
	return nothing
end

function slug(text::AbstractString)::String
	folded = Unicode.normalize(lowercase(text); stripmark = true)
	trimmed = strip(replace(folded, r"[^a-z0-9]+" => "_"), '_')
	isempty(trimmed) && return "x"
	return trimmed
end

mutable struct Identifiers
	used::Set{String}
end

Identifiers() = Identifiers(Set{String}())

# `normalize = false` where slugging again would flatten a sense's positional dots
function mint!(
	identifiers::Identifiers, candidate::AbstractString; normalize::Bool = true,
)::String
	base = normalize ? slug(candidate) : candidate
	name = base
	counter = 1
	while name in identifiers.used
		counter += 1
		name = "$(base)_$(counter)"
	end
	push!(identifiers.used, name)
	return name
end

"""
    sense_candidate(prefix, index, nested)

Positional, not a collision counter: `angoisse_s3` is the entry's third sense and
`angoisse_s3.2` the second sense inside it. `mint!` still guards genuine collisions,
since homographs normalize to the same headword slug, but no longer supplies the
ordinal.
"""
sense_candidate(prefix::AbstractString, index::Int, nested::Bool)::String =
	nested ? string(prefix, '.', index) : string(prefix, "_s", index)

const NameTable = Dict{RawSpan, String}

"""
    assign_names(corpus)

Every `xml:id` the document will carry, minted in render order and keyed by raw anchor.
A cross-reference can only be pointed at a target whose identifier is already known, so
naming happens in its own pass and the render walk does no minting at all.

A form-bearing node needs two names: one for its nested `<entry>` and one for the
`<sense>` inside it. Both are recorded, and a reference to that node resolves to the
entry.
"""
struct NodeNames
	entry::Union{Nothing, String}
	sense::String
end

struct Names
	entries::NameTable
	nodes::Dict{RawSpan, NodeNames}
	citations::NameTable
	rubrique_notes::NameTable
end

Names(entries, nodes, citations) = Names(entries, nodes, citations, NameTable())

function name_node!(
	names::Names,
	identifiers::Identifiers,
	node::Resolve.ResolvedNode,
	prefix::AbstractString,
	index::Int,
	nested::Bool,
)
	if Adjudication.form_bearing(node.node_type)
		candidate = string(prefix, "_", slug(something(node.form, "")))
		entry = mint!(identifiers, candidate; normalize = false)
		inner = mint!(identifiers, sense_candidate(entry, 1, false); normalize = false)
		names.nodes[node.span] = NodeNames(entry, inner)
		name_children!(names, identifiers, node, inner)
	else
		candidate = sense_candidate(prefix, index, nested)
		sense = mint!(identifiers, candidate; normalize = false)
		names.nodes[node.span] = NodeNames(nothing, sense)
		name_children!(names, identifiers, node, sense)
	end
	return nothing
end

# form-bearing children are named from their form, so they take no positional slot
function name_children!(
	names::Names,
	identifiers::Identifiers,
	node::Resolve.ResolvedNode,
	prefix::AbstractString,
)
	position = 0
	for child in node.children
		if !Adjudication.form_bearing(child.node_type)
			position += 1
		end
		name_node!(names, identifiers, child, prefix, position, true)
	end
	return nothing
end

# definition content that is nothing but punctuation; carried as `<pc>`
function punctuation_only(definition::Vector{Resolve.Inline})::Bool
	isempty(definition) && return false
	return all(definition) do item
		item isa Resolve.TextRun || return false
		text = strip(item.text)
		return !isempty(text) && all(ispunct, text)
	end
end

function render_punctuation(io::IO, definition::Vector{Resolve.Inline})
	write(io, "<pc>")
	for item in definition
		write(io, escape_xml(strip(item.text)))
	end
	write(io, "</pc>")
	return nothing
end

function assign_names(corpus::Resolve.ResolvedCorpus)::Names
	identifiers = Identifiers()
	names = Names(
		NameTable(), Dict{RawSpan, NodeNames}(), NameTable(), NameTable(),
	)
	for entry in corpus.entries
		name = mint!(identifiers, entry.headword)
		names.entries[entry.span] = name
		position = 0
		for node in entry.nodes
			position += 1
			name_node!(names, identifiers, node, name, position, false)
		end
		for rubrique in entry.rubriques, item in rubrique.items
			item isa Resolve.RubriqueNode || continue
			position += 1
			name_node!(names, identifiers, item.node, name, position, false)
		end
		proverb_prose = [
			item for rubrique in entry.rubriques
			if Resolve.conventions_for(rubrique.name).note == "proverb"
			for item in rubrique.items if item isa Resolve.RubriqueProse
		]
		sort!(proverb_prose; by = item -> item.span.start_byte)
		for (note_position, prose) in enumerate(proverb_prose)
			candidate = string(name, "_proverb_", note_position)
			names.rubrique_notes[prose.span] =
				mint!(identifiers, candidate; normalize = false)
		end
		citations = Resolve.all_entry_citations(entry)
		sort!(citations; by = citation -> citation.span.start_byte)
		for (citation_position, citation) in enumerate(citations)
			names.citations[citation.span] = mint!(
				identifiers, string(name, "_c", citation_position); normalize = false,
			)
		end
	end
	return names
end

"""
    target_name(names, resolved)

The identifier a resolved cross-reference points at, or `nothing`. The compliance
contract admits an internal `target="#xml-id"` only where the target is reliably
resolved, and prefers a textual reference to a guessed pointer, so an unresolved
reference emits `<ref>` without `@target`.
"""
function target_name(
	names::Names, resolved::Union{Nothing, RawSpan},
)::Union{Nothing, String}
	isnothing(resolved) && return nothing
	haskey(names.entries, resolved) && return names.entries[resolved]
	haskey(names.nodes, resolved) || return nothing
	node = names.nodes[resolved]
	return something(node.entry, node.sense)
end

function render_inline_item(
	io::IO, item::Resolve.CrossReference, names::Names, wrap_cross_reference::Bool,
)
	target = optional_reference("target", target_name(names, item.resolved))
	reference = string(
		"<ref type=\"entry\"", target, ">", escape_xml(item.text), "</ref>",
	)
	wrap_cross_reference || return write(io, reference)
	return write(io, "<xr type=\"related\">", reference, "</xr>")
end

function render_inline_item(io::IO, item::Resolve.Emphasis, ::Names, ::Bool)
	language = optional_attribute("xml:lang", item.language)
	example = item.source_element == "exemple"
	opening = example ? "seg type=\"example\"" : "hi rend=\"italic\""
	closing = example ? "seg" : "hi"
	return write(
		io, "<", opening, language, ">", escape_xml(item.text), "</", closing, ">",
	)
end

render_inline_item(io::IO, item::Resolve.TextRun, ::Names, ::Bool) =
	write(io, escape_xml(item.text))

# `<def>` and `<quote>` admit `<xr>`; `<seg>` admits only the bare `<ref>`
function render_inline(
	io::IO,
	items::Vector{Resolve.Inline},
	names::Names;
	wrap_cross_reference::Bool = true,
)
	for item in items
		render_inline_item(io, item, names, wrap_cross_reference)
	end
	return nothing
end

function render_qualification(io::IO, qualification::Resolve.Qualification)
	norm = optional_attribute("norm", qualification.norm)
	element = qualification.channel == :usg ? "usg" : "gram"
	write(
		io, "<", element, " type=\"", escape_attribute(qualification.type), "\"",
		norm, ">", escape_xml(qualification.printed), "</", element, ">",
	)
	return nothing
end

function render_usg(
	io::IO, qualifications::Vector{Resolve.Qualification}, depth::Int,
)
	for qualification in qualifications
		qualification.channel == :usg || continue
		newline(io, depth)
		render_qualification(io, qualification)
	end
	return nothing
end

same_grammatical_marker(left::Resolve.Qualification, right::Resolve.Qualification) =
	left.marker_printed == right.marker_printed && left.span == right.span

function render_grammatical_marker(
	io::IO, qualifications::Vector{Resolve.Qualification},
)
	marker = first(qualifications).marker_printed
	positions = UnitRange{Int}[]
	cursor = firstindex(marker)
	for qualification in qualifications
		position = findnext(qualification.printed, marker, cursor)
		if isnothing(position)
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
	return nothing
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
	return nothing
end

has_grammar(qualifications::Vector{Resolve.Qualification})::Bool =
	any(item -> item.channel == :gram, qualifications)

antecedent_name(::Names, ::Nothing)::Union{Nothing, String} = nothing

antecedent_name(names::Names, antecedent::RawSpan)::Union{Nothing, String} =
	names.citations[antecedent]

function render_citation(
	io::IO,
	citation::Resolve.Citation,
	names::Names;
	subtype::AbstractString = "",
	depth::Int = 0,
	date_text::AbstractString = "",
	not_before = nothing,
	not_after = nothing,
	corresp::Union{Nothing, String} = nothing,
)
	write(
		io, "<cit type=\"example\" xml:id=\"", names.citations[citation.span], "\"",
		optional_attribute("subtype", subtype),
		optional_reference("corresp", corresp), ">",
	)
	newline(io, depth + 1)
	write(io, "<quote>")
	render_inline(io, citation.quotation, names)
	write(io, "</quote>")
	dated = !isnothing(not_before) && !isnothing(not_after)
	described =
		dated ||
		!isempty(citation.resolved_author) ||
		!isempty(citation.author) ||
		!isempty(citation.reference)
	if described
		newline(io, depth + 1)
		write(io, "<bibl>")
		if !isempty(citation.author)
			newline(io, depth + 2)
			antecedent = antecedent_name(names, citation.author_antecedent)
			write(
				io, "<author", optional_reference("corresp", antecedent), ">",
				escape_xml(citation.author), "</author>",
			)
		end
		if !isempty(citation.reference)
			newline(io, depth + 2)
			antecedent = antecedent_name(names, citation.reference_antecedent)
			write(
				io, "<biblScope", optional_reference("corresp", antecedent), ">",
				escape_xml(citation.reference), "</biblScope>",
			)
		end
		# duplicated into each bibl so the corpus is queryable by date
		if dated
			newline(io, depth + 2)
			# xsd:gYear, so a tenth-century range is 0901 rather than 901
			write(
				io, "<date notBefore=\"", lpad(not_before, 4, '0'),
				"\" notAfter=\"", lpad(not_after, 4, '0'), "\">",
				escape_xml(date_text), "</date>",
			)
		end
		newline(io, depth + 1)
		write(io, "</bibl>")
	end
	newline(io, depth)
	write(io, "</cit>")
	return nothing
end

"""
    render_node(io, node, names, depth)

A node with an underdetermined type is serialized as `<sense><def>…</def></sense>`
without implying that an adjudicator positively established an ordinary sense. A
positively asserted `SubLemma` becomes a nested `<entry type="relatedEntry">`, which is
what lets a sub-lemma sit inside the sense that contains it.
"""
# a form-bearing pronominal alternant is entry-like: Littré opens a subsidiary entry
nested_entry_type(::Adjudication.SubLemma)::Union{Nothing, String} = "relatedEntry"
nested_entry_type(::Adjudication.VoiceVariant)::Union{Nothing, String} =
	"homonymicEntry"
nested_entry_type(::Any)::Union{Nothing, String} = nothing

function render_definition(
	io::IO, definition::Vector{Resolve.Inline}, names::Names, depth::Int,
)
	isempty(definition) && return nothing
	newline(io, depth)
	punctuation_only(definition) && return render_punctuation(io, definition)
	write(io, "<def>")
	render_inline(io, definition, names)
	write(io, "</def>")
	return nothing
end

function render_citations(
	io::IO,
	citations::Vector{Resolve.Citation},
	names::Names,
	depth::Int,
	citation_subtype::AbstractString,
)
	for citation in citations
		newline(io, depth)
		render_citation(io, citation, names; subtype = citation_subtype, depth)
	end
	return nothing
end

function render_node(
	io::IO, node::Resolve.ResolvedNode, names::Names, depth::Int,
	rubriques::Vector{Resolve.ResolvedRubrique} = Resolve.ResolvedRubrique[],
	citation_subtype::AbstractString = "",
)
	entry_type = nested_entry_type(node.node_type)
	isnothing(entry_type) ||
		return render_nested_entry(io, node, names, entry_type, depth, citation_subtype)
	name = names.nodes[node.span].sense
	number = optional_attribute("n", node.number)
	write(io, "<sense xml:id=\"", name, "\"", number, ">")
	render_usg(io, node.qualifications, depth + 1)
	if has_grammar(node.qualifications)
		newline(io, depth + 1)
		render_grammar(io, node.qualifications)
	end
	render_definition(io, node.definition, names, depth + 1)
	render_citations(io, node.citations, names, depth + 1, citation_subtype)
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
	return nothing
end

function render_nested_entry(
	io::IO,
	node::Resolve.ResolvedNode,
	names::Names,
	entry_type::AbstractString,
	depth::Int,
	citation_subtype::AbstractString = "",
)
	name = something(names.nodes[node.span].entry, "")
	write(
		io, "<entry xml:id=\"", name, "\" xml:lang=\"", object_language,
		"\" type=\"", entry_type, "\">",
	)
	for (index, form) in enumerate(node.forms)
		newline(io, depth + 1)
		form_type = index == 1 ? "lemma" : "variant"
		write(io, "<form type=\"", form_type, "\"><orth")
		if isnothing(form.value)
			write(io, ">", escape_xml(form.printed), "</orth></form>")
		else
			write(io, " value=\"", escape_attribute(form.value), "\"/></form>")
		end
	end
	if has_grammar(node.qualifications)
		newline(io, depth + 1)
		render_grammar(io, node.qualifications)
	end
	# printed between a form and its gloss, belonging to neither span
	if !isnothing(node.separator)
		newline(io, depth + 1)
		write(io, "<pc>", escape_xml(node.separator), "</pc>")
	end
	newline(io, depth + 1)
	write(io, "<sense xml:id=\"", names.nodes[node.span].sense, "\">")
	render_usg(io, node.qualifications, depth + 2)
	render_definition(io, node.definition, names, depth + 2)
	render_citations(io, node.citations, names, depth + 2, citation_subtype)
	for child in node.children
		newline(io, depth + 2)
		render_node(
			io, child, names, depth + 2, Resolve.ResolvedRubrique[], citation_subtype,
		)
	end
	newline(io, depth + 1)
	write(io, "</sense>")
	newline(io, depth)
	write(io, "</entry>")
	return nothing
end

function render_etym_forms(io::IO, forms::Vector{String}, italic::Bool)
	form_type = length(forms) > 1 ? " type=\"variant\"" : ""
	rend = italic ? " rend=\"italic\"" : ""
	for form in forms
		write(
			io, "<form", form_type, "><orth", rend, ">",
			escape_xml(form), "</orth></form>",
		)
	end
	return nothing
end

function render_etym_cue(io::IO, cue::Resolve.EtymCue)
	write(
		io, "<lang", optional_attribute("expand", cue.expand),
		" norm=\"", escape_attribute(cue.code), "\">",
		escape_xml(cue.printed), "</lang>",
	)
	isempty(cue.trailing) || write(io, "<pc>", escape_xml(cue.trailing), "</pc>")
	return nothing
end

render_etym_cue(::IO, ::Nothing) = nothing

function render_etym_segment(io::IO, cit::Resolve.EtymCit, ::Names)
	language = optional_attribute("xml:lang", cit.language)
	write(io, "<cit type=\"", String(cit.cit_type), "\"", language, ">")
	render_etym_cue(io, cit.cue)
	# the reconstruction marker has no Lex-0 element; the established fallback is a hint
	cit.fictif && write(io, "<usg type=\"hint\">fictif</usg>")
	render_etym_forms(io, cit.forms, cit.italic)
	isempty(cit.gloss) || write(io, "<gloss>", escape_xml(cit.gloss), "</gloss>")
	write(io, "</cit>")
	return nothing
end

function render_etym_segment(io::IO, component::Resolve.EtymComponent, ::Names)
	language = isempty(component.language) ? "fr" : component.language
	write(io, "<cit type=\"etymon\" xml:lang=\"", escape_attribute(language), "\">")
	render_etym_forms(io, component.forms, component.italic)
	write(io, "</cit>")
	return nothing
end

render_etym_segment(io::IO, literal::Resolve.EtymLiteral, ::Names) =
	@match literal.printed begin
		";" || ":" => write(io, " <pc>", literal.printed, "</pc> ")
		","        => write(io, "<pc>,</pc> ")
		"."        => write(io, "<pc>.</pc>")
		printed    => write(io, "<pc>", escape_xml(printed), "</pc>")
	end

render_etym_segment(io::IO, connector::Resolve.EtymConnector, ::Names) =
	write(io, " ", escape_xml(connector.printed), " ")

# preserved rather than silently corrected; the epistemic claim rides on @ana
render_etym_segment(io::IO, suspect::Resolve.EtymSuspect, ::Names) =
	write(io, "<lbl ana=\"suspect\">", escape_xml(suspect.token), "</lbl>")

render_etym_segment(io::IO, prose::Resolve.EtymProse, ::Names) =
	write(io, "<seg>", escape_xml(prose.text), "</seg>")

function render_etym_segment(
	io::IO, reference::Resolve.EtymCrossReference, names::Names,
)
	isempty(reference.label) ||
		write(io, "<lbl>", escape_xml(reference.label), "</lbl>")
	target = optional_reference("target", target_name(names, reference.resolved))
	write(
		io, "<ref type=\"entry\"", target, ">",
		escape_xml(reference.printed), "</ref>",
	)
	return nothing
end

"""
    render_rubrique(io, rubrique, names, depth)

`<note>` cannot hold `<cit>` under Lex-0, so a rubrique's citations are lifted to entry
level while its prose stays in a note. Items are emitted in source order, which keeps a
century label adjacent to the attestations it introduces. The rubrique boundary is
therefore not expressed in TEI; the `subtype` and the rubrique's raw anchor in SQLite
carry that association instead.
"""
rubriques_under_rubrique(
	rubriques::Vector{Resolve.ResolvedRubrique}, parent::Resolve.ResolvedRubrique,
) = filter(rubrique -> rubrique.parent_id == anchor_id(parent.span), rubriques)

rubrique_part_span(item::Resolve.RubriqueItem) = Resolve.rubrique_item_span(item)
rubrique_part_span(rubrique::Resolve.ResolvedRubrique) = rubrique.span
rubrique_part_span(group::Vector{Resolve.AnchoredEtymSegment}) =
	first(group).container_span

function etymology_groups(
	etymology::Vector{Resolve.AnchoredEtymSegment},
)::Vector{Vector{Resolve.AnchoredEtymSegment}}
	groups = Vector{Resolve.AnchoredEtymSegment}[]
	for anchored in etymology
		new_group =
			isempty(groups) ||
			first(last(groups)).container_span != anchored.container_span
		if new_group
			push!(groups, Resolve.AnchoredEtymSegment[])
		end
		push!(last(groups), anchored)
	end
	return groups
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
		return nothing
	end
	conventions = Resolve.conventions_for(rubrique.name)
	proverb = conventions.note == "proverb"
	proverb_note_id = nothing
	heading = Resolve.rubrique_heading(rubrique.name)
	parts = Any[]
	append!(parts, etymology_groups(rubrique.etymology))
	append!(parts, rubrique.items)
	append!(parts, rubriques_under_rubrique(rubriques, rubrique))
	sort!(parts; by = part -> rubrique_part_span(part).start_byte)
	combine_heading =
		!isnothing(heading) && proverb &&
		!isempty(parts) && first(parts) isa Resolve.RubriqueProse
	if !isnothing(heading) && !combine_heading
		next_item!()
		write(
			io, "<note type=\"", escape_attribute(conventions.note),
			"\" subtype=\"label\">", escape_xml(heading), "</note>",
		)
	end
	proverb_heading = combine_heading ? heading : nothing
	for part in parts
		next_item!()
		@match part begin
			group::Vector{Resolve.AnchoredEtymSegment} => begin
				write(io, "<etym>")
				for anchored in group
					render_etym_segment(io, anchored.segment, names)
				end
				write(io, "</etym>")
			end
			nested::Resolve.ResolvedRubrique =>
				render_rubrique(io, nested, names, depth, rubriques)
			prose::Resolve.RubriqueProse => begin
				render_rubrique_item(
					io, prose, names, conventions.note, conventions.subtype, depth;
					heading = proverb_heading,
				)
				if proverb
					proverb_note_id = names.rubrique_notes[prose.span]
					proverb_heading = nothing
				end
			end
			citation::Resolve.RubriqueCitation => render_rubrique_item(
				io, citation, names, conventions.note, conventions.subtype, depth;
				corresp = proverb ? proverb_note_id : nothing,
			)
			item => render_rubrique_item(
				io, item, names, conventions.note, conventions.subtype, depth,
			)
		end
	end
	return nothing
end

render_rubrique_item(
	io::IO,
	label::Resolve.RubriqueLabel,
	::Names,
	::AbstractString,
	::AbstractString,
	::Int,
) = write(
	io, "<lbl type=\"", escape_attribute(label.kind), "\">",
	escape_xml(label.text), "</lbl>",
)

function render_rubrique_item(
	io::IO,
	citation::Resolve.RubriqueCitation,
	names::Names,
	::AbstractString,
	::AbstractString,
	depth::Int;
	corresp::Union{Nothing, String} = nothing,
)
	return render_citation(
		io, citation.citation, names;
		subtype = citation.subtype, depth, date_text = citation.date_text,
		not_before = citation.not_before, not_after = citation.not_after, corresp,
	)
end

function render_rubrique_item(
	io::IO,
	prose::Resolve.RubriqueProse,
	names::Names,
	note_type::AbstractString,
	::AbstractString,
	::Int;
	heading::Union{Nothing, String} = nothing,
)
	proverb = note_type == "proverb"
	note_id = proverb ? names.rubrique_notes[prose.span] : nothing
	write(
		io, "<note type=\"", escape_attribute(note_type), "\"",
		optional_attribute("xml:id", note_id), ">",
	)
	if proverb
		isnothing(heading) ||
			write(io, "<seg type=\"label\">", escape_xml(heading), "</seg> ")
		render_inline(io, prose.content, names; wrap_cross_reference = false)
	else
		write(io, "<seg>")
		render_inline(io, prose.content, names; wrap_cross_reference = false)
		write(io, "</seg>")
	end
	write(io, "</note>")
	return nothing
end

function render_rubrique_item(
	io::IO,
	item::Resolve.RubriqueNode,
	names::Names,
	::AbstractString,
	citation_subtype::AbstractString,
	depth::Int,
)
	render_node(
		io, item.node, names, depth, Resolve.ResolvedRubrique[], citation_subtype,
	)
	return nothing
end

"""
    rubriques_under(rubriques, node_id)

The rubriques the source placed inside a given block. Littré writes PROVERBE inside the
very sense it illustrates; emitting every rubrique at entry level would keep the
material but lose which sense it belonged to. A rubrique whose parent is the entry, or
another rubrique, is not claimed here.
"""
rubriques_under(rubriques::Vector{Resolve.ResolvedRubrique}, node_id::AbstractString) =
	filter(rubrique -> rubrique.parent_id == node_id, rubriques)

function flatten_nodes(
	nodes::Vector{Resolve.ResolvedNode},
)::Vector{Resolve.ResolvedNode}
	flattened = Resolve.ResolvedNode[]
	visit(current) = for node in current
		push!(flattened, node)
		visit(node.children)
	end
	visit(nodes)
	return flattened
end

renderable(rubrique::Resolve.ResolvedRubrique)::Bool =
	!isempty(rubrique.items) || !isempty(rubrique.etymology)

function renderable(
	rubrique::Resolve.ResolvedRubrique, rubriques::Vector{Resolve.ResolvedRubrique},
)::Bool
	renderable(rubrique) && return true
	nested = rubriques_under_rubrique(rubriques, rubrique)
	return any(child -> renderable(child, rubriques), nested)
end

function render_entry(io::IO, entry::Resolve.ResolvedEntry, names::Names, depth::Int)
	name = names.entries[entry.span]
	write(
		io, "<entry xml:id=\"", name, "\" xml:lang=\"", object_language,
		"\" type=\"mainEntry\">",
	)
	newline(io, depth + 1)
	write(io, "<form type=\"lemma\"><orth>", escape_xml(entry.headword), "</orth>")
	isnothing(entry.pronunciation) ||
		write(io, "<pron>", escape_xml(entry.pronunciation), "</pron>")
	write(io, "</form>")
	if has_grammar(entry.grammar)
		newline(io, depth + 1)
		render_grammar(io, entry.grammar)
	end
	render_usg(io, entry.grammar, depth + 1)
	for note in entry.header
		newline(io, depth + 1)
		write(io, "<note type=\"", Resolve.header_note_type, "\">")
		render_inline(io, note.content, names; wrap_cross_reference = false)
		write(io, "</note>")
	end
	for node in entry.nodes
		newline(io, depth + 1)
		render_node(io, node, names, depth + 1, entry.rubriques)
	end
	# source order: entry content is unordered under Lex-0, so no house order is imposed
	claimed = Set(
		rubrique.span for node in flatten_nodes(entry.nodes)
		for rubrique in rubriques_under(entry.rubriques, node.node_id)
	)
	rubrique_ids = Set(anchor_id(rubrique.span) for rubrique in entry.rubriques)
	nested = Set(
		rubrique.span for rubrique in entry.rubriques
		if !isnothing(rubrique.parent_id) && rubrique.parent_id in rubrique_ids
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
	return nothing
end

function render_tei(
	corpus::Resolve.ResolvedCorpus,
	path::AbstractString;
	header::AbstractString = tei_header(),
)
	names = assign_names(corpus)
	open(path, "w") do handle
		write(handle, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
		write(
			handle,
			"<TEI xmlns=\"http://www.tei-c.org/ns/1.0\" xml:id=\"littre\" type=\"lex-0\">\n",
		)
		write(handle, header)
		write(handle, "\n  <text>\n    <body>\n")
		for entry in corpus.entries
			indent(handle, 3)
			render_entry(handle, entry, names, 3)
		end
		write(handle, "    </body>\n  </text>\n</TEI>\n")
	end
	return path
end

function tei_header()::String
	path = joinpath(normpath(joinpath(@__DIR__, "..", "..")), "data", "tei_header.xml")
	isfile(path) || error("missing TEI header at $(path)")
	return strip(read(path, String))
end
