"""
Resolution combines two qualitatively different inputs without conflating them: deterministic
facts reconstructed from explicit source markup, and durable judgments read from the adjudication
store. Deleting the store must still yield a coarse corpus carrying every explicit XMLittré fact.
"""
struct AdjudicationState
	applicable::Dict{Tuple{String, Int, Int}, Vector{Adjudication.AppliedRecord}}
	stale::Vector{Adjudication.ExaminationRecord}
	findings::Vector{ReviewFinding}
end

review_category(reason::AbstractString)::Union{Nothing, String} =
	startswith(reason, "structural conflict:") ? "structural_conflict" :
	endswith(reason, " is unresolved") ? "unresolved" :
	nothing

function record_review!(state::AdjudicationState, block::Census.SourceBlock, reason::AbstractString)
	category = review_category(reason)
	category === nothing && return nothing
	push!(state.findings, ReviewFinding(category, reason, block.raw_span))
	nothing
end

function adjudication_state(
	harness::Adjudication.Harness,
	passes::Vector{String} = String[pass.pass for pass in Adjudication.current_passes];
	strict::Bool = false,
)::AdjudicationState
	Adjudication.validate_store(harness)
	applicable = Dict{Tuple{String, Int, Int}, Vector{Adjudication.AppliedRecord}}()
	stale = Adjudication.ExaminationRecord[]
	seen_record_ids = Set{String}()
	for pass in passes
		for record in Adjudication.read_pass(harness.store, pass)
			record.record_id in seen_record_ids && throw(Adjudication.StoreIntegrityError(
				"duplicate record id $(record.record_id) across adjudication passes",
			))
			push!(seen_record_ids, record.record_id)
			applied = Adjudication.materialize_record(harness, record)
			if applied === nothing
				strict && error("strict build: record $(record.record_id) is stale")
				push!(stale, record)
			else
				push!(get!(applicable, Adjudication.anchor_key(applied.source),
					Adjudication.AppliedRecord[]), applied)
			end
		end
	end
	AdjudicationState(applicable, stale, ReviewFinding[])
end

records_for(state::AdjudicationState, block::Census.SourceBlock, pass::AbstractString) =
	filter(record -> record.pass == pass,
		get(state.applicable, Adjudication.anchor_key(block.raw_span), Adjudication.AppliedRecord[]))

function sole(records::Vector{Adjudication.AppliedRecord})
	isempty(records) && return nothing
	length(records) == 1 || throw(Adjudication.StoreIntegrityError(
		"$(length(records)) applicable records for $(first(records).source) in pass $(first(records).pass)",
	))
	only(records)
end

function structural_assertions(
	state::AdjudicationState, block::Census.SourceBlock,
)::Vector{Adjudication.AnchoredNodeAssertion}
	assertions = Adjudication.AnchoredNodeAssertion[]
	for pass in Adjudication.structural_passes
		record = sole(records_for(state, block, pass.pass))
		(record === nothing || record.outcome != :positive) && continue
		append!(assertions, record.assertions)
	end
	assertions
end

same_span(left::RawSpan, right::RawSpan)::Bool =
	Source.covers(left, right) && Source.covers(right, left)

strictly_covers(outer::RawSpan, inner::RawSpan)::Bool =
	!same_span(outer, inner) && Source.covers(outer, inner)

function structural_conflict(
	assertions::Vector{Adjudication.AnchoredNodeAssertion},
)::Union{Nothing, String}
	ids = Set{String}()
	for assertion in assertions
		assertion.node_id in ids && return "duplicate node id $(assertion.node_id)"
		push!(ids, assertion.node_id)
	end
	for outer in eachindex(assertions), inner in (outer + 1):lastindex(assertions)
		left = assertions[outer]
		right = assertions[inner]
		same_span(left.span, right.span) && return "coincident node spans $(left.span) for $(left.node_id) and $(right.node_id)"
		Source.laminar(left.span, right.span) || return "node spans cross: $(left.span) and $(right.span)"
	end
	nothing
end

function geometric_parent_indices_unchecked(
	assertions::Vector{Adjudication.AnchoredNodeAssertion},
)::Vector{Union{Nothing, Int}}
	parents = Union{Nothing, Int}[nothing for _ in assertions]
	for child in eachindex(assertions)
		candidates = Int[
			parent for parent in eachindex(assertions)
			if parent != child && strictly_covers(assertions[parent].span, assertions[child].span)
		]
		isempty(candidates) && continue
		parents[child] = first(sort(candidates; by = parent -> length(assertions[parent].span)))
	end
	parents
end

function geometric_parent_indices(
	assertions::Vector{Adjudication.AnchoredNodeAssertion},
)::Vector{Union{Nothing, Int}}
	structural_conflict(assertions) === nothing || error("cannot derive parentage for conflicting assertions")
	geometric_parent_indices_unchecked(assertions)
end

function closure(state::AdjudicationState, block::Census.SourceBlock)::Tuple{Bool, String}
	passes = Adjudication.structural_passes
	isempty(passes) && return (false, "no structural pass is declared")
	all(passes) do pass
		Adjudication.population_predicate(pass.population)(block.kind)
	end || return (false, "outside the structural population")
	conflict = structural_conflict(structural_assertions(state, block))
	conflict === nothing || return (false, "structural conflict: $(conflict)")
	for pass in passes
		record = sole(records_for(state, block, pass.pass))
		record === nothing && return (false, "$(pass.pass) has not examined this block")
		record.outcome == :unresolved && return (false, "$(pass.pass) is unresolved")
	end
	(true, "")
end

function qualification_markers(
	document::Source.SourceDocument, node::XML.FlatNode,
)::Tuple{Vector{Qualification}, Vector{ViewSpan}}
	qualifications = Qualification[]
	spans = ViewSpan[]
	for child in XML.children(node)
		XML.nodetype(child) == XML.Element || continue
		name = XML.tag(child)
		name in ("semantique", "nature") || continue
		span = Source.node_view_span(document, child)
		raw = Source.to_raw(document.transform, span)[1]
		content = collapse_inline(document, child)
		isempty(content) && continue
		append!(qualifications, route_qualifications(content, raw))
		push!(spans, span)
	end
	(qualifications, spans)
end


function bare_qualification_markers(
	document::Source.SourceDocument, state::AdjudicationState, block::Census.SourceBlock,
)::Tuple{Vector{Qualification}, Vector{ViewSpan}}
	record = sole(records_for(state, block, Adjudication.bare_qualification_pass.pass))
	(record === nothing || record.outcome != :positive) && return (Qualification[], ViewSpan[])
	node = Adjudication.element_at(document, block.view_span)
	projection = Adjudication.project(document, node)
	qualifications = Qualification[]
	spans = ViewSpan[]
	seen = Set{Tuple{String, Int, Int}}()
	for scope in record.scopes
		key = (scope.marker.file, scope.marker.start_byte, scope.marker.end_byte)
		key in seen && continue
		push!(seen, key)
		view = Source.to_view(document.transform, scope.marker)
		content = Adjudication.projected_text(projection, view)
		for qualification in route_qualifications(content, scope.marker)
			push!(qualifications, rescope(qualification, AssertedScope(scope.target)))
		end
		push!(spans, view)
	end
	(qualifications, spans)
end

function route_qualifications(content::AbstractString, span::RawSpan)::Vector{Qualification}
	qualifications = Qualification[]
	for (target, printed) in route_spans(content)
		if target isa UsgTarget
			push!(qualifications, Qualification(:usg, target.kind, target.norm, printed, span))
		else
			for element in target
				element_printed = length(target) == 1 ? printed : element.printed
				push!(qualifications, Qualification(
					:gram, element.kind, element.norm, element_printed, printed, span,
				))
			end
		end
	end
	qualifications
end

const anaphoric_author = "ID."
const anaphoric_reference_pattern = r"(?i)^ib\."

struct CitationAnaphora
	resolved_author::String
	author_resolution::Symbol
	author_antecedent::Union{Nothing, RawSpan}
	reference_antecedent::Union{Nothing, RawSpan}
	reference_resolution::Symbol
end

function build_citation(
	document::Source.SourceDocument, node::XML.FlatNode, span::ViewSpan,
	resolution::Dict{Int, CitationAnaphora}, references::CrossReferenceIndex,
)::Citation
	printed = something(Source.attribute(node, "aut"), "")
	reference = something(Source.attribute(node, "ref"), "")
	default = CitationAnaphora(
		printed, isempty(printed) ? :absent : :printed, nothing, nothing,
		isempty(reference) ? :absent : :printed,
	)
	anaphora = get(resolution, span.start_byte, default)
	Citation(
		Source.to_raw(document.transform, span)[1],
		inline_content(document, node, ViewSpan[], references),
		printed,
		anaphora.resolved_author,
		anaphora.author_resolution,
		anaphora.author_antecedent,
		reference,
		anaphora.reference_antecedent,
		anaphora.reference_resolution,
	)
end

function author_resolution(
	document::Source.SourceDocument, entry::XML.FlatNode,
)::Dict{Int, CitationAnaphora}
	found = Tuple{Int, RawSpan, String, String}[]
	collect_citations!(found, document, entry)
	sort!(found; by = first)
	resolution = Dict{Int, CitationAnaphora}()
	previous_span = nothing
	previous_author = ""
	previous_author_resolution = :none
	for (position, span, author, reference) in found
		author_antecedent = nothing
		if author == anaphoric_author
			author_antecedent = previous_span
			if previous_span === nothing || previous_author_resolution in (:none, :unresolved)
				resolved_author, author_resolution = author, :unresolved
			elseif isempty(previous_author)
				resolved_author, author_resolution = "", :antecedent_absent
			else
				resolved_author, author_resolution = previous_author, :resolved
			end
		else
			resolved_author = author
			author_resolution = isempty(author) ? :absent : :printed
		end
		reference_anaphoric = occursin(anaphoric_reference_pattern, reference)
		reference_antecedent = reference_anaphoric ? previous_span : nothing
		reference_resolution = reference_anaphoric ?
			(previous_span === nothing ? :unresolved : :resolved) :
			(isempty(reference) ? :absent : :printed)
		resolution[position] = CitationAnaphora(
			resolved_author, author_resolution, author_antecedent,
			reference_antecedent, reference_resolution,
		)
		previous_span = span
		previous_author = resolved_author
		previous_author_resolution = author_resolution
	end
	resolution
end

function collect_citations!(
	found::Vector{Tuple{Int, RawSpan, String, String}}, document::Source.SourceDocument,
	node::XML.FlatNode,
)
	for child in XML.children(node)
		XML.nodetype(child) == XML.Element || continue
		if XML.tag(child) == "cit"
			view = Source.node_view_span(document, child)
			push!(found, (
				view.start_byte, Source.to_raw(document.transform, view)[1],
				something(Source.attribute(child, "aut"), ""),
				something(Source.attribute(child, "ref"), ""),
			))
		else
			collect_citations!(found, document, child)
		end
	end
	nothing
end

function citations(
	document::Source.SourceDocument, node::XML.FlatNode,
	resolution::Dict{Int, CitationAnaphora}, references::CrossReferenceIndex,
)::Tuple{Vector{Citation}, Vector{ViewSpan}}
	found = Citation[]
	spans = ViewSpan[]
	for child in XML.children(node)
		XML.nodetype(child) == XML.Element && XML.tag(child) == "cit" || continue
		span = Source.node_view_span(document, child)
		push!(spans, span)
		push!(found, build_citation(document, child, span, resolution, references))
	end
	(found, spans)
end

function asserted_nodes(
	document::Source.SourceDocument, state::AdjudicationState, block::Census.SourceBlock,
)::Tuple{Vector{ResolvedNode}, Vector{ViewSpan}}
	assertions = structural_assertions(state, block)
	structural_conflict(assertions) === nothing || return (ResolvedNode[], ViewSpan[])
	parents = geometric_parent_indices(assertions)
	children = [Int[] for _ in assertions]
	roots = Int[]
	for index in eachindex(assertions)
		parent = parents[index]
		if parent === nothing
			push!(roots, index)
		else
			push!(children[parent], index)
		end
	end
	for group in children
		sort!(group; by = index -> assertions[index].span.start_byte)
	end
	sort!(roots; by = index -> assertions[index].span.start_byte)

	projection = Adjudication.project(document, Adjudication.element_at(document, block.view_span))
	visible(span::RawSpan)::String = Adjudication.projected_text(
		projection, Source.to_view(document.transform, span),
	)

	function build(index::Int)::ResolvedNode
		assertion = assertions[index]
		form_assertions = filter(item -> item.name == "form", assertion.constituents)
		forms = NodeForm[
			NodeForm(item.span, visible(item.span), item.value) for item in form_assertions
		]
		gloss_assertion = findfirst(item -> item.name == "gloss", assertion.constituents)
		gloss = gloss_assertion === nothing ? nothing : assertion.constituents[gloss_assertion].span
		separator_form = isempty(forms) ? nothing : last(sort(forms; by = item -> item.span.end_byte)).span
		constituents = NodeConstituent[
			NodeConstituent(item.name, item.span, visible(item.span), item.value)
			for item in assertion.constituents
		]
		ResolvedNode(
			Source.anchor_id(assertion.span),
			assertion.node_type,
			assertion.span,
			nothing,
			isempty(forms) ? nothing : form_value(first(forms)),
			forms,
			constituents,
			separator_between(document, separator_form, gloss),
			gloss === nothing ? Inline[] : Inline[TextRun(visible(gloss), gloss)],
			Qualification[],
			Citation[],
			ResolvedNode[build(child) for child in children[index]],
		)
	end

	spans = ViewSpan[Source.to_view(document.transform, assertion.span) for assertion in assertions]
	(ResolvedNode[build(index) for index in roots], spans)
end

"""
	separator_between(document, form, gloss)

The raw material lying between two adjacent constituents. Littré separates a sub-lemma's form
from its gloss with punctuation that sits in neither span, so without this the comma in
`Avaler des poires d'angoisse, subir des mortifications` is unreconstructible downstream.
"""
function separator_between(
	document::Source.SourceDocument, form::Union{Nothing, RawSpan}, gloss::Union{Nothing, RawSpan},
)::Union{Nothing, String}
	(form === nothing || gloss === nothing) && return nothing
	gloss.start_byte > form.end_byte || return nothing
	between = strip(Source.slice(
		document.raw_text, RawSpan(form.file, form.end_byte, gloss.start_byte),
	))
	# Material carrying markup is a qualification marker or a nested structure, not punctuation;
	# it is attached by containment rather than presented as a separator.
	(isempty(between) || occursin('<', between)) ? nothing : String(between)
end

function resolve_block(
	harness::Adjudication.Harness, state::AdjudicationState, block::Census.SourceBlock,
	resolution::Dict{Int, CitationAnaphora}, references::CrossReferenceIndex,
)::ResolvedNode
	document = harness.documents[block.raw_span.file]
	node = Adjudication.element_at(document, block.view_span)

	(resolved, reason) = closure(state, block)
	isempty(reason) || record_review!(state, block, reason)

	(qualifications, marker_spans) = qualification_markers(document, node)
	(bare_qualifications, bare_marker_spans) = bare_qualification_markers(document, state, block)
	append!(qualifications, bare_qualifications)
	append!(marker_spans, bare_marker_spans)
	(quotations, citation_spans) = citations(document, node, resolution, references)
	(asserted, asserted_spans) = asserted_nodes(document, state, block)
	children = ResolvedNode[
		resolve_block(harness, state, child, resolution, references) for child in block.children
	]
	child_spans = ViewSpan[child.view_span for child in block.children]

	# Default parentage is laminar containment: a qualification marker or citation lying inside an
	# asserted node belongs to that node, not to the block enclosing it. This is geometry, not
	# scope inference — a marker outside every node stays where the source put it.
	#
	# An adjudicated scope overrides that geometry, and only that: it moves where a marker applies,
	# never what the marker means, which stays deterministic.
	qualifications = apply_scopes(state, block, qualifications)
	asserted = ResolvedNode[attach_contained(item, qualifications, quotations) for item in asserted]
	qualifications = filter(
		item -> !attaches_to_any(item, asserted), qualifications,
	)
	quotations = filter(item -> !contained_in_any(item.span, asserted), quotations)

	excluded = vcat(marker_spans, citation_spans, asserted_spans, child_spans)
	definition = inline_content(document, node, excluded, references)

	ResolvedNode(
		Source.anchor_id(block.raw_span),
		resolved ? Adjudication.Sense() : nothing,
		block.raw_span,
		Source.attribute(node, "num"),
		nothing,
		NodeForm[],
		NodeConstituent[],
		nothing,
		definition,
		qualifications,
		quotations,
		merge_source_children(asserted, children),
	)
end

contained_in_any(span::RawSpan, nodes::Vector{ResolvedNode})::Bool =
	any(node -> Source.covers(node.span, span), nodes)

"""
	apply_scopes(state, block, qualifications)

Rewrite each marker's scope target from any applicable scope adjudication. A marker with no
adjudication keeps `ContainedScope`, which is a stated geometric rule rather than a guess, so the
absence of a record never becomes a claim.
"""
function apply_scopes(
	state::AdjudicationState, block::Census.SourceBlock, qualifications::Vector{Qualification},
)::Vector{Qualification}
	for pass in Adjudication.scope_passes
		record = sole(records_for(state, block, pass.pass))
		(record === nothing || record.outcome != :positive) && continue
		qualifications = Qualification[
			rescope_from(record, qualification) for qualification in qualifications
		]
	end
	qualifications
end

function rescope_from(
	record::Adjudication.AppliedRecord, qualification::Qualification,
)::Qualification
	for scope in record.scopes
		scope.marker == qualification.span || continue
		return rescope(qualification, AssertedScope(scope.target))
	end
	qualification
end

scope_span(qualification::Qualification)::RawSpan =
	qualification.scope isa AssertedScope ? qualification.scope.target : qualification.span

attaches_to(qualification::Qualification, node::ResolvedNode)::Bool =
	Source.covers(node.span, scope_span(qualification))

attaches_to_any(qualification::Qualification, nodes::Vector{ResolvedNode})::Bool =
	any(node -> attaches_to(qualification, node), nodes)

function attach_contained(
	node::ResolvedNode, qualifications::Vector{Qualification}, quotations::Vector{Citation},
)::ResolvedNode
	children = ResolvedNode[attach_contained(child, qualifications, quotations) for child in node.children]
	ResolvedNode(
		node.node_id, node.node_type, node.span, node.number, node.form, node.forms, node.constituents,
		node.separator, node.definition,
		filter(item -> attaches_to(item, node) && !attaches_to_any(item, children), qualifications),
		filter(item -> Source.covers(node.span, item.span) && !contained_in_any(item.span, children), quotations),
		children,
	)
end

function with_children(node::ResolvedNode, children::Vector{ResolvedNode})::ResolvedNode
	ResolvedNode(
		node.node_id, node.node_type, node.span, node.number, node.form, node.forms, node.constituents,
		node.separator, node.definition, node.qualifications, node.citations, children,
	)
end

function insert_source_child(node::ResolvedNode, child::ResolvedNode)::ResolvedNode
	Source.covers(node.span, child.span) || return node
	children = copy(node.children)
	for index in eachindex(children)
		Source.covers(children[index].span, child.span) || continue
		children[index] = insert_source_child(children[index], child)
		return with_children(node, children)
	end
	push!(children, child)
	sort!(children; by = item -> item.span.start_byte)
	with_children(node, children)
end

function merge_source_children(
	asserted::Vector{ResolvedNode}, source_children::Vector{ResolvedNode},
)::Vector{ResolvedNode}
	roots = copy(asserted)
	for child in source_children
		placed = false
		for index in eachindex(roots)
			Source.covers(roots[index].span, child.span) || continue
			roots[index] = insert_source_child(roots[index], child)
			placed = true
			break
		end
		placed || push!(roots, child)
	end
	sort!(roots; by = item -> item.span.start_byte)
	roots
end

"""
	inner_span(document, node)

The parser-view interval between an element's open and close tags. The etymology segmenter is
ported from v0.2 and consumes source markup directly, so it needs the element's content bytes
rather than a projection.
"""
function inner_span(document::Source.SourceDocument, node::XML.FlatNode)::ViewSpan
	span = Source.node_view_span(document, node)
	children = collect(XML.children(node))
	isempty(children) && return ViewSpan(span.file, span.end_byte, span.end_byte)
	first_child = Source.node_view_span(document, first(children))
	last_child = Source.node_view_span(document, last(children))
	ViewSpan(span.file, first_child.start_byte, last_child.end_byte)
end

const etymology_rubrique = "ÉTYMOLOGIE"

# Lex-0 leaves lbl/@type and cit/@subtype unconstrained, so these values are project convention.
# They are policed at the output — a test builds its whitelist from this table and fails a value
# in rendered TEI that is not in it — rather than declared anywhere else.
const rubrique_conventions = Dict(
	"ÉTYMOLOGIE" => (note = "", subtype = ""),
	"HISTORIQUE" => (note = "historical", subtype = "attestation"),
	"SYNONYME" => (note = "synonymy", subtype = "synonym"),
	"REMARQUE" => (note = "usage", subtype = "remark"),
	"REMARQUES" => (note = "usage", subtype = "remark"),
	"PROVERBE" => (note = "proverb", subtype = "proverb"),
	"PROVERBES" => (note = "proverb", subtype = "proverb"),
	"SUPPLÉMENT AU DICTIONNAIRE" => (note = "supplement", subtype = "supplement"),
)

conventions_for(name::AbstractString) =
	get(rubrique_conventions, name, (note = "other", subtype = "other"))

# The one note type that is not a rubrique convention. It names a position in the entry header, so
# it has no entry in the table above and is whitelisted by the same output test from here.
const header_note_type = "header"

const rubrique_headings = Dict(
	"PROVERBE" => "Proverbe.",
	"PROVERBES" => "Proverbes.",
)

rubrique_heading(name::AbstractString) = get(rubrique_headings, name, nothing)

# A century header is printed once over the group of attestations it introduces. Recognition is a
# committed pattern with counted residue, not an inference: unmatched lead text stays prose and
# becomes a review finding. HISTORIQUE also has a deterministic supplement marker, `Ajoutez :`,
# which may precede or follow the century token.
const century_pattern = r"^(?:\(\*\)\s*)?([IVXLC]+)e\.?\s+s\.$"
const century_first_lead_pattern =
	r"^\s*((?:\(\*\)\s*)?([IVXLC]+)e\.?\s+s\.)(?:\s*(Ajoutez\s*:))?"
const supplement_first_lead_pattern =
	r"^\s*(Ajoutez\s*:)(?:\s*((?:\(\*\)\s*)?([IVXLC]+)e\.?\s+s\.))?"
const supplement_label = "supplement"

const date_range_label = "dateRange"

const roman_values = Dict('I' => 1, 'V' => 5, 'X' => 10, 'L' => 50, 'C' => 100)

function roman_value(numeral::AbstractString)::Union{Nothing, Int}
	total = 0
	previous = 0
	for character in reverse(numeral)
		value = get(roman_values, character, nothing)
		value === nothing && return nothing
		total += value < previous ? -value : value
		previous = max(previous, value)
	end
	1 <= total <= 20 ? total : nothing
end

"""
	century_range(text)

The half-open Gregorian years a printed century header covers, as `(not_before, not_after)`, or
`nothing` when the header does not parse. `XVIe s.` is 1501–1600: the ordinal names the century, not
the years.
"""
function century_range(text::AbstractString)
	found = match(century_pattern, text)
	found === nothing && return nothing
	century = roman_value(found.captures[1])
	century === nothing ? nothing : ((century - 1) * 100 + 1, century * 100)
end

function century_years(numeral::AbstractString)
	century = roman_value(numeral)
	century === nothing ? nothing : ((century - 1) * 100 + 1, century * 100)
end

function lead_capture_span(
	span::ViewSpan, found::RegexMatch, capture_index::Int,
)::Union{Nothing, ViewSpan}
	offset = found.offsets[capture_index]
	offset < 1 && return nothing
	printed = found.captures[capture_index]
	printed === nothing && return nothing
	start_byte = span.start_byte + offset - 1
	ViewSpan(span.file, start_byte, start_byte + ncodeunits(printed))
end

function normalized_lead_text(text::AbstractString)::String
	strip(replace(text, r"\s+" => " "))
end

function historique_lead(
	document::Source.SourceDocument, nodes::Vector{XML.FlatNode},
)::Tuple{Vector{RubriqueLabel}, Vector{ViewSpan}}
	isempty(nodes) && return (RubriqueLabel[], ViewSpan[])
	first_node = first(nodes)
	XML.nodetype(first_node) == XML.Text || return (RubriqueLabel[], ViewSpan[])
	span = Source.node_view_span(document, first_node)
	text = String(Source.slice(document.parser_view, span))
	found = match(century_first_lead_pattern, text)
	order = :century_first
	if found === nothing
		found = match(supplement_first_lead_pattern, text)
		order = :supplement_first
	end
	found === nothing && return (RubriqueLabel[], ViewSpan[])

	labels = RubriqueLabel[]
	excluded = ViewSpan[]
	function push_label!(kind::String, capture_index::Int, numeral_index::Int = 0)
		view_span = lead_capture_span(span, found, capture_index)
		view_span === nothing && return nothing
		printed = normalized_lead_text(String(Source.slice(document.parser_view, view_span)))
		raw_span = Source.to_raw(document.transform, view_span)[1]
		if numeral_index == 0
			push!(labels, RubriqueLabel(kind, printed, nothing, nothing, raw_span))
		else
			years = century_years(found.captures[numeral_index])
			years === nothing && return nothing
			push!(labels, RubriqueLabel(date_range_label, printed, years[1], years[2], raw_span))
		end
		push!(excluded, view_span)
		nothing
	end

	if order == :century_first
		push_label!(date_range_label, 1, 2)
		push_label!(supplement_label, 3)
	else
		push_label!(supplement_label, 1)
		push_label!(date_range_label, 2, 3)
	end
	(labels, excluded)
end

function projected_citation_offset(
	projection::Adjudication.ProjectedView, citation::ViewSpan,
)::Int
	positions = Int[
		segment.projected_end for segment in projection.segments
		if !segment.synthetic && segment.view_end <= citation.start_byte
	]
	isempty(positions) ? 1 : maximum(positions)
end

function attach_projected_citations(
	document::Source.SourceDocument, block::Census.SourceBlock,
	nodes::Vector{ResolvedNode}, quotations::Vector{Citation}, citation_spans::Vector{ViewSpan},
)::Vector{ResolvedNode}
	isempty(nodes) && return nodes
	projection = Adjudication.project(document, Adjudication.element_at(document, block.view_span))
	flat = ResolvedNode[]
	visit(items) = for node in items
		push!(flat, node)
		visit(node.children)
	end
	visit(nodes)
	projected = Dict{String, Adjudication.ProjectedSpan}()
	for node in flat
		span = Adjudication.to_projected(projection, Source.to_view(document.transform, node.span))
		span === nothing || (projected[node.node_id] = span)
	end
	assigned = Dict{String, Vector{Citation}}()
	for (quotation, citation_span) in zip(quotations, citation_spans)
		offset = projected_citation_offset(projection, citation_span)
		candidates = ResolvedNode[
			node for node in flat if haskey(projected, node.node_id) &&
			projected[node.node_id].start_byte <= offset <= projected[node.node_id].end_byte
		]
		isempty(candidates) && continue
		target = first(sort(candidates; by = node -> length(projected[node.node_id])))
		push!(get!(assigned, target.node_id, Citation[]), quotation)
	end
	function rewrite(node::ResolvedNode)::ResolvedNode
		children = ResolvedNode[rewrite(child) for child in node.children]
		citations = copy(node.citations)
		seen = Set((citation.span.file, citation.span.start_byte, citation.span.end_byte) for citation in citations)
		for citation in get(assigned, node.node_id, Citation[])
			key = (citation.span.file, citation.span.start_byte, citation.span.end_byte)
			key in seen && continue
			push!(citations, citation)
			push!(seen, key)
		end
		sort!(citations; by = citation -> citation.span.start_byte)
		ResolvedNode(
			node.node_id, node.node_type, node.span, node.number, node.form, node.forms, node.constituents,
			node.separator, node.definition, node.qualifications, citations, children,
		)
	end
	ResolvedNode[rewrite(node) for node in nodes]
end

function resolve_rubrique_block_nodes(
	harness::Adjudication.Harness, state::AdjudicationState, block::Census.SourceBlock,
	resolution::Dict{Int, CitationAnaphora}, references::CrossReferenceIndex,
)::Vector{ResolvedNode}
	document = harness.documents[block.raw_span.file]
	node = Adjudication.element_at(document, block.view_span)
	conflict = structural_conflict(structural_assertions(state, block))
	conflict === nothing || record_review!(state, block, "structural conflict: $(conflict)")
	(qualifications, _) = qualification_markers(document, node)
	(bare_qualifications, _) = bare_qualification_markers(document, state, block)
	append!(qualifications, bare_qualifications)
	(quotations, citation_spans) = citations(document, node, resolution, references)
	(asserted, _) = asserted_nodes(document, state, block)
	children = ResolvedNode[]
	for child in block.children
		append!(children, resolve_rubrique_block_nodes(harness, state, child, resolution, references))
	end
	qualifications = apply_scopes(state, block, qualifications)
	asserted = ResolvedNode[attach_contained(item, qualifications, quotations) for item in asserted]
	asserted = attach_projected_citations(document, block, asserted, quotations, citation_spans)
	merge_source_children(asserted, children)
end

function rubrique_semantic_nodes(
	harness::Adjudication.Harness, state::AdjudicationState, rubrique::Census.SourceRubrique,
	resolution::Dict{Int, CitationAnaphora}, references::CrossReferenceIndex,
)::Vector{ResolvedNode}
	nodes = ResolvedNode[]
	for block in rubrique.blocks
		append!(nodes, resolve_rubrique_block_nodes(harness, state, block, resolution, references))
	end
	sort!(nodes; by = node -> node.span.start_byte)
	nodes
end

function semantic_exclusions(
	document::Source.SourceDocument, nodes::Vector{ResolvedNode},
)::Tuple{Vector{ViewSpan}, Vector{RawSpan}}
	views = ViewSpan[]
	spans = RawSpan[]
	function visit(items)
		for node in items
			push!(spans, node.span)
			push!(views, Source.to_view(document.transform, node.span))
			for qualification in node.qualifications
				push!(views, Source.to_view(document.transform, qualification.span))
			end
			for citation in node.citations
				push!(views, Source.to_view(document.transform, citation.span))
			end
			visit(node.children)
		end
	end
	visit(nodes)
	(views, spans)
end

function split_rubrique_content(
	content::Vector{Inline}, separators::Vector{RawSpan},
)::Vector{Vector{Inline}}
	isempty(content) && return Vector{Inline}[]
	groups = Vector{Inline}[Inline[first(content)]]
	previous = first(content).span
	for item in Iterators.drop(content, 1)
		span = item.span
		cut = any(separator ->
			previous.end_byte <= separator.start_byte && separator.end_byte <= span.start_byte,
			separators,
		)
		cut && push!(groups, Inline[])
		push!(last(groups), item)
		previous = span
	end
	groups
end

function rubrique_item_span(item::RubriqueLabel)::RawSpan
	item.span
end

function rubrique_item_span(item::RubriqueCitation)::RawSpan
	item.citation.span
end

function rubrique_item_span(item::RubriqueProse)::RawSpan
	item.span
end

function rubrique_item_span(item::RubriqueNode)::RawSpan
	item.node.span
end

function resolve_rubrique(
	harness::Adjudication.Harness, state::AdjudicationState, rubrique::Census.SourceRubrique,
	resolution::Dict{Int, CitationAnaphora}, references::CrossReferenceIndex,
	findings::Vector{ReviewFinding}, headword::AbstractString,
)::ResolvedRubrique
	document = harness.documents[rubrique.raw_span.file]
	node = Adjudication.element_at(document, rubrique.view_span)
	items = RubriqueItem[]
	etymology = AnchoredEtymSegment[]
	semantic_nodes = rubrique_semantic_nodes(harness, state, rubrique, resolution, references)
	(excluded, semantic_spans) = semantic_exclusions(document, semantic_nodes)
	conventions = conventions_for(rubrique.name)
	if rubrique.name == etymology_rubrique
		for child in XML.children(node)
			XML.nodetype(child) == XML.Element && XML.tag(child) in ("indent", "variante") || continue
			append!(etymology, segment_paragraph(document, child, references, headword))
		end
		if !isempty(semantic_nodes)
			etymology = AnchoredEtymSegment[
				segment for segment in etymology
				if !any(span -> Source.covers(span, segment.span), semantic_spans)
			]
			append!(items, RubriqueNode[RubriqueNode(node) for node in semantic_nodes])
		end
	else
		items = carry_date_range(rubrique_items(
			document, node, rubrique, conventions, resolution, references, findings;
			excluded, semantic_spans,
		))
		append!(items, RubriqueNode[RubriqueNode(node) for node in semantic_nodes])
		sort!(items; by = item -> rubrique_item_span(item).start_byte)
	end
	ResolvedRubrique(rubrique.name, rubrique.raw_span, rubrique.parent_id, items, etymology)
end

function rubrique_items(
	document::Source.SourceDocument, node::XML.FlatNode, rubrique::Census.SourceRubrique,
	conventions, resolution::Dict{Int, CitationAnaphora}, references::CrossReferenceIndex,
	findings::Vector{ReviewFinding}; excluded::Vector{ViewSpan} = ViewSpan[],
	semantic_spans::Vector{RawSpan} = RawSpan[],
)::Vector{RubriqueItem}
	items = RubriqueItem[]
	pending = XML.FlatNode[]
	leading = true

	function flush!()
		isempty(pending) && return nothing
		labels = RubriqueLabel[]
		lead_excluded = ViewSpan[]
		if leading && rubrique.name == "HISTORIQUE"
			labels, lead_excluded = historique_lead(document, pending)
			append!(items, labels)
		end
		content = inline_from(document, pending, references; excluded = vcat(excluded, lead_excluded))
		empty!(pending)
		for group in split_rubrique_content(content, semantic_spans)
			isempty(group) && continue
			span = RawSpan(
				rubrique.raw_span.file,
				first(group).span.start_byte,
				last(group).span.end_byte,
			)
			text = strip(plain_text(group))
			range = century_range(text)
			if leading && isempty(labels) && range !== nothing
				push!(items, RubriqueLabel(date_range_label, String(text), range[1], range[2], span))
			elseif !isempty(text)
				push!(items, RubriqueProse(group, span))
				leading && rubrique.name == "HISTORIQUE" && isempty(labels) &&
					push!(findings, ReviewFinding(
						"century_unrecognized", String(first(text, 60)), span,
					))
			end
		end
		nothing
	end

	for child in XML.children(node)
		name = XML.nodetype(child) == XML.Element ? XML.tag(child) : ""
		if name == "cit"
			flush!()
			leading = false
			span = Source.node_view_span(document, child)
			carved(span, excluded) && continue
			push!(items, RubriqueCitation(
				build_citation(document, child, span, resolution, references), conventions.subtype,
			))
		elseif name == "indent" || name == "variante"
			flush!()
			leading = false
			child_span = Source.node_view_span(document, child)
			child_excluded = ViewSpan[
				span for span in excluded if !Source.covers(span, child_span)
			]
			append!(items, rubrique_items(
				document, child, rubrique, conventions, resolution, references, findings;
				excluded = child_excluded, semantic_spans,
			))
		else
			push!(pending, child)
		end
	end
	flush!()
	items
end

"""
	carry_date_range(items)

Attach the most recent century header to each following citation. Items are already in source
order, so the header printed over a group of attestations reaches every member of that group and
stops at the next header.
"""
function carry_date_range(items::Vector{RubriqueItem})::Vector{RubriqueItem}
	date_text = ""
	not_before = nothing
	not_after = nothing
	carried = RubriqueItem[]
	for item in items
		if item isa RubriqueLabel && item.kind == date_range_label
			date_text = item.text
			not_before = item.not_before
			not_after = item.not_after
			push!(carried, item)
		elseif item isa RubriqueCitation
			push!(carried, RubriqueCitation(
				item.citation, item.subtype, date_text, not_before, not_after,
			))
		else
			push!(carried, item)
		end
	end
	carried
end

function segment_paragraph(
	document::Source.SourceDocument, node::XML.FlatNode, references::CrossReferenceIndex,
	headword::AbstractString,
)::Vector{AnchoredEtymSegment}
	inner = inner_span(document, node)
	isempty(inner) && return AnchoredEtymSegment[]
	content = String(Source.slice(document.parser_view, inner))
	(block, _) = Source.to_raw(document.transform, inner)
	anchored = AnchoredEtymSegment[]
	for segment in segment_etymology(content; headword)
		range = segment_range(segment)
		span = if isempty(range)
			block
		else
			Source.to_raw(document.transform, ViewSpan(
				inner.file,
				inner.start_byte + first(range) - 1,
				inner.start_byte + last(range),
			))[1]
		end
		push!(anchored, AnchoredEtymSegment(resolve_segment(segment, references), span, block))
	end
	anchored
end

carries_text(text::AbstractString)::Bool =
	any(character -> isletter(character) || isdigit(character), text)

const printed_form = r"[A-ZÀ-ÞŒÆ]{2,}"

"""
	qualifying_natures(document, header)

How many of the entete's `<nature>` elements qualify the headword itself. The first always does. A
later one does only if nothing since the one before announces a second headword form, which the
source announces in one of two ways: the form printed in capitals, as in
`ACCORDÉ … ACCORDÉE (a-kordée) <nature>s. f.</nature>`, or a further `<prononciation>`, as in
`COBÆA ou COBÉE`. Intervening prose alone does not demote a label — TARGUER prints its conjugation
between `v. a.` and `v. réfl.` and both describe the headword.
"""
function qualifying_natures(document::Source.SourceDocument, header::XML.FlatNode)::Int
	qualifying = 0
	second_form = false
	for child in XML.children(header)
		kind = XML.nodetype(child)
		if kind == XML.Text
			occursin(printed_form, Source.slice(
				document.parser_view, Source.node_view_span(document, child),
			)) && (second_form = true)
		elseif kind == XML.Element
			name = XML.tag(child)
			if name == "nature"
				qualifying > 0 && second_form && return qualifying
				qualifying += 1
				second_form = false
			elseif name == "prononciation" || occursin(printed_form, collapse_inline(document, child))
				second_form = true
			end
		end
	end
	qualifying
end

function entry_grammar(document::Source.SourceDocument, node::XML.FlatNode)::Vector{Qualification}
	header = Source.element_children(node, "entete")
	isempty(header) && return Qualification[]
	qualifications = Qualification[]
	natures = Source.element_children(first(header), "nature")
	for nature in natures[1:qualifying_natures(document, first(header))]
		span = Source.to_raw(document.transform, Source.node_view_span(document, nature))[1]
		append!(qualifications, route_qualifications(collapse_inline(document, nature), span))
	end
	qualifications
end

"""
	entry_header(document, node, references)

The entete material that is neither the entry's pronunciation nor a label qualifying it, as one note
per contiguous run. The first `<prononciation>` and the qualifying `<nature>` elements are the
boundaries; everything between them — loose text, an `<indent>`, a cross-reference, and the
pronunciation and label of any further headword form — belongs to the run it sits in. A run that
prints no letter or digit is separator punctuation and carries nothing.
"""
function entry_header(
	document::Source.SourceDocument, node::XML.FlatNode, references::CrossReferenceIndex,
)::Vector{HeaderNote}
	header = Source.element_children(node, "entete")
	isempty(header) && return HeaderNote[]
	remaining = qualifying_natures(document, first(header))
	spoken = true
	notes = HeaderNote[]
	pending = XML.FlatNode[]
	function flush!()
		isempty(pending) && return nothing
		content = inline_from(document, pending, references)
		empty!(pending)
		(isempty(content) || !carries_text(plain_text(content))) && return nothing
		push!(notes, HeaderNote(content, RawSpan(
			first(content).span.file,
			first(content).span.start_byte,
			last(content).span.end_byte,
		)))
		nothing
	end
	for child in XML.children(first(header))
		name = XML.nodetype(child) == XML.Element ? XML.tag(child) : ""
		if name == "prononciation" && spoken
			spoken = false
			flush!()
		elseif name == "nature" && remaining > 0
			remaining -= 1
			flush!()
		else
			push!(pending, child)
		end
	end
	flush!()
	notes
end

function entry_pronunciation(
	document::Source.SourceDocument, node::XML.FlatNode,
)::Union{Nothing, String}
	header = Source.element_children(node, "entete")
	isempty(header) && return nothing
	spoken = Source.element_children(first(header), "prononciation")
	isempty(spoken) && return nothing
	content = collapse_inline(document, first(spoken))
	isempty(content) ? nothing : content
end

function resolve_entry(
	harness::Adjudication.Harness, state::AdjudicationState, entry::Census.SourceEntry,
	references::CrossReferenceIndex, findings::Vector{ReviewFinding},
)::ResolvedEntry
	document = harness.documents[entry.raw_span.file]
	node = Adjudication.element_at(document, entry.view_span)
	resolution = author_resolution(document, node)
	ResolvedEntry(
		entry.source_id,
		entry.headword,
		entry.homograph,
		entry.raw_span,
		entry_pronunciation(document, node),
		entry_grammar(document, node),
		entry_header(document, node, references),
		ResolvedNode[resolve_block(harness, state, block, resolution, references) for block in entry.blocks
			if !(block.kind isa Census.EnteteNature || block.kind isa Census.EnteteIndent)],
		ResolvedRubrique[
			resolve_rubrique(harness, state, rubrique, resolution, references, findings, entry.headword)
			for rubrique in entry.rubriques
		],
	)
end

function entry_citations(entry::ResolvedEntry)::Vector{Citation}
	found = Citation[]
	gather(nodes) = for node in nodes
		append!(found, node.citations)
		gather(node.children)
	end
	gather(entry.nodes)
	for rubrique in entry.rubriques
		for item in rubrique.items
			item isa RubriqueNode || continue
			gather(ResolvedNode[item.node])
		end
	end
	found
end

function all_entry_citations(entry::ResolvedEntry)::Vector{Citation}
	found = entry_citations(entry)
	for rubrique in entry.rubriques
		for item in rubrique.items
			item isa RubriqueCitation || continue
			push!(found, item.citation)
		end
	end
	found
end

function coverage(
	harness::Adjudication.Harness, state::AdjudicationState, pass::Adjudication.PassDefinition,
)::PassCoverage
	population = Adjudication.eligible(pass, harness.corpus)
	examined = Adjudication.AppliedRecord[]
	for block in population
		record = sole(records_for(state, block, pass.pass))
		record === nothing || push!(examined, record)
	end
	PassCoverage(
		pass.pass, pass.pass_version, pass.population, pass.population_version,
		length(population), Census.population_hash(population),
		length(examined),
		count(record -> record.outcome == :positive, examined),
		count(record -> record.outcome == :negative, examined),
		count(record -> record.outcome == :unresolved, examined),
		count(record -> record.pass == pass.pass, state.stale),
	)
end

function check_node_identity(entries::Vector{ResolvedEntry})
	seen = Set{String}()
	function visit(nodes::Vector{ResolvedNode})
		for node in nodes
			node.node_id in seen &&
				error("two resolved nodes share the anchor $(node.node_id)")
			push!(seen, node.node_id)
			visit(node.children)
		end
	end
	for entry in entries
		visit(entry.nodes)
		for rubrique in entry.rubriques
			for item in rubrique.items
				item isa RubriqueNode || continue
				visit(ResolvedNode[item.node])
			end
		end
	end
	nothing
end

function resolve(
	harness::Adjudication.Harness; strict::Bool = false, progress = nothing,
)::ResolvedCorpus
	state = adjudication_state(harness; strict)
	references = cross_reference_index(harness.corpus)
	entries = ResolvedEntry[]
	for document in harness.corpus.documents
		elapsed = @elapsed resolved = ResolvedEntry[
			resolve_entry(harness, state, entry, references, state.findings)
			for entry in document.entries
		]
		append!(entries, resolved)
		progress === nothing || progress(document.file, length(resolved), elapsed)
	end
	check_node_identity(entries)
	unresolved_authors = ReviewFinding[
		ReviewFinding("author_unresolved", "ID. with no antecedent in the entry", citation.span)
		for entry in entries for citation in all_entry_citations(entry)
		if citation.resolution == :unresolved && citation.author_antecedent === nothing
	]
	unresolved_references = ReviewFinding[
		ReviewFinding("reference_unresolved", "ib. with no antecedent in the entry", citation.span)
		for entry in entries for citation in all_entry_citations(entry)
		if citation.reference_resolution == :unresolved
	]
	suspects = ReviewFinding[
		ReviewFinding("etymology_suspect", anchored.segment.token, anchored.span)
		for entry in entries for rubrique in entry.rubriques
		for anchored in rubrique.etymology if anchored.segment isa EtymSuspect
	]
	unsegmented = ReviewFinding[
		ReviewFinding("etymology_unsegmented", String(anchored.segment.fallback), anchored.span)
		for entry in entries for rubrique in entry.rubriques
		for anchored in rubrique.etymology
		if anchored.segment isa EtymProse && anchored.segment.fallback != :none
	]
	review = vcat(
		ReviewFinding[
			ReviewFinding("stale", record.record_id, record.source)
			for record in state.stale
		],
		state.findings,
		suspects,
		unsegmented,
		unresolved_authors,
		unresolved_references,
	)
	ResolvedCorpus(entries, review, PassCoverage[
		coverage(harness, state, pass) for pass in Adjudication.current_passes
	])
end
