"""
Resolution combines two qualitatively different inputs without conflating them:
deterministic facts reconstructed from explicit source markup, and durable judgments
read from the adjudication store. Deleting the store must still yield a coarse corpus
carrying every explicit XMLittré fact.
"""
const AnchorKey = Tuple{String, Int, Int}


# ===== adjudication state =====

struct AdjudicationState
	applicable::Dict{AnchorKey, Vector{Adjudication.AppliedRecord}}
	stale::Vector{Adjudication.ExaminationRecord}
	findings::Vector{ReviewFinding}
end

function review_category(reason::AbstractString)::Union{Nothing, String}
	startswith(reason, "structural conflict:") && return "structural_conflict"
	endswith(reason, " is unresolved") && return "unresolved"
	return nothing
end

function record_review!(
	state::AdjudicationState, block::Census.SourceBlock, reason::AbstractString,
)
	category = review_category(reason)
	isnothing(category) && return nothing
	push!(state.findings, ReviewFinding(category, reason, block.raw_span))
	return nothing
end

function adjudication_state(
	harness::Adjudication.Harness,
	passes::Vector{String} = String[pass.pass for pass in Adjudication.current_passes];
	strict::Bool = false,
)::AdjudicationState
	Adjudication.validate_store(harness)
	applicable = Dict{AnchorKey, Vector{Adjudication.AppliedRecord}}()
	stale = Adjudication.ExaminationRecord[]
	seen_record_ids = Set{String}()
	for pass in passes, record in Adjudication.read_pass(harness.store, pass)
		record.record_id in seen_record_ids && Adjudication.integrity_error(
			"duplicate record id $(record.record_id) across adjudication passes",
		)
		push!(seen_record_ids, record.record_id)
		applied = Adjudication.materialize_record!(harness, record)
		if isnothing(applied)
			strict && error("strict build: record $(record.record_id) is stale")
			push!(stale, record)
		else
			key = Adjudication.anchor_key(applied.source)
			push!(get!(applicable, key, Adjudication.AppliedRecord[]), applied)
		end
	end
	return AdjudicationState(applicable, stale, ReviewFinding[])
end

function records_for(
	state::AdjudicationState, block::Census.SourceBlock, pass::AbstractString,
)
	key = Adjudication.anchor_key(block.raw_span)
	applicable = get(state.applicable, key, Adjudication.AppliedRecord[])
	return filter(record -> record.pass == pass, applicable)
end

function sole(records::Vector{Adjudication.AppliedRecord})
	isempty(records) && return nothing
	length(records) == 1 || Adjudication.integrity_error(
		"$(length(records)) applicable records for $(first(records).source) " *
		"in pass $(first(records).pass)",
	)
	return only(records)
end


# ===== structural geometry =====

function structural_assertions(
	state::AdjudicationState, block::Census.SourceBlock,
)::Vector{Adjudication.AnchoredNodeAssertion}
	assertions = Adjudication.AnchoredNodeAssertion[]
	for pass in Adjudication.structural_passes
		record = sole(records_for(state, block, pass.pass))
		(isnothing(record) || record.outcome != :positive) && continue
		append!(assertions, record.assertions)
	end
	return assertions
end

strictly_covers(outer::RawSpan, inner::RawSpan)::Bool =
	outer != inner && Source.covers(outer, inner)

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
		left.span == right.span && return "coincident node spans $(left.span) " *
			"for $(left.node_id) and $(right.node_id)"
		Source.laminar(left.span, right.span) ||
			return "node spans cross: $(left.span) and $(right.span)"
	end
	return nothing
end

function geometric_parent_indices_unchecked(
	assertions::Vector{Adjudication.AnchoredNodeAssertion},
)::Vector{Union{Nothing, Int}}
	parents = Union{Nothing, Int}[nothing for _ in assertions]
	for child in eachindex(assertions)
		candidates = Int[
			parent for parent in eachindex(assertions)
			if parent != child &&
				strictly_covers(assertions[parent].span, assertions[child].span)
		]
		isempty(candidates) && continue
		narrowest = sort(candidates; by = parent -> length(assertions[parent].span))
		parents[child] = first(narrowest)
	end
	return parents
end

function geometric_parent_indices(
	assertions::Vector{Adjudication.AnchoredNodeAssertion},
)::Vector{Union{Nothing, Int}}
	isnothing(structural_conflict(assertions)) ||
		error("cannot derive parentage for conflicting assertions")
	return geometric_parent_indices_unchecked(assertions)
end

function closure(
	state::AdjudicationState, block::Census.SourceBlock,
)::Tuple{Bool, String}
	passes = Adjudication.structural_passes
	isempty(passes) && return (false, "no structural pass is declared")
	all(passes) do pass
		Adjudication.population_predicate(pass.population)(block.kind)
	end || return (false, "outside the structural population")
	conflict = structural_conflict(structural_assertions(state, block))
	isnothing(conflict) || return (false, "structural conflict: $(conflict)")
	for pass in passes
		record = sole(records_for(state, block, pass.pass))
		isnothing(record) && return (false, "$(pass.pass) has not examined this block")
		record.outcome == :unresolved && return (false, "$(pass.pass) is unresolved")
	end
	return (true, "")
end


# ===== qualification markers =====

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
		content = collapse_inline(document, child)
		isempty(content) && continue
		append!(qualifications, route_qualifications(content, to_raw(document, span)))
		push!(spans, span)
	end
	return (qualifications, spans)
end

function bare_qualification_markers(
	document::Source.SourceDocument,
	state::AdjudicationState,
	block::Census.SourceBlock,
)::Tuple{Vector{Qualification}, Vector{ViewSpan}}
	record = sole(records_for(state, block, Adjudication.bare_qualification_pass.pass))
	(isnothing(record) || record.outcome != :positive) &&
		return (Qualification[], ViewSpan[])
	node = Adjudication.element_at(document, block.view_span)
	projection = Adjudication.project(document, node)
	qualifications = Qualification[]
	spans = ViewSpan[]
	seen = Set{AnchorKey}()
	for scope in record.scopes
		key = Adjudication.anchor_key(scope.marker)
		key in seen && continue
		push!(seen, key)
		view_span = Source.to_view(document.transform, scope.marker)
		content = Adjudication.projected_text(projection, view_span)
		for qualification in route_qualifications(content, scope.marker)
			push!(qualifications, rescope(qualification, AssertedScope(scope.target)))
		end
		push!(spans, view_span)
	end
	return (qualifications, spans)
end

function route_qualifications(
	content::AbstractString, span::RawSpan,
)::Vector{Qualification}
	qualifications = Qualification[]
	for (target, printed) in route_spans(content)
		if target isa UsgTarget
			push!(qualifications, Qualification(
				:usg, target.kind, target.norm, printed, span,
			))
		else
			for element in target
				element_printed = length(target) == 1 ? printed : element.printed
				push!(qualifications, Qualification(
					:gram, element.kind, element.norm, element_printed, span;
					marker_printed = printed,
				))
			end
		end
	end
	return qualifications
end


# ===== citations and anaphora =====

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
	return Citation(
		to_raw(document, span),
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
			unresolved_antecedent = previous_author_resolution in (:none, :unresolved)
			if isnothing(previous_span) || unresolved_antecedent
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
		reference_resolution = if !reference_anaphoric
			isempty(reference) ? :absent : :printed
		else
			isnothing(previous_span) ? :unresolved : :resolved
		end
		resolution[position] = CitationAnaphora(
			resolved_author, author_resolution, author_antecedent,
			reference_antecedent, reference_resolution,
		)
		previous_span = span
		previous_author = resolved_author
		previous_author_resolution = author_resolution
	end
	return resolution
end

function collect_citations!(
	found::Vector{Tuple{Int, RawSpan, String, String}}, document::Source.SourceDocument,
	node::XML.FlatNode,
)
	for child in XML.children(node)
		XML.nodetype(child) == XML.Element || continue
		if XML.tag(child) == "cit"
			span = Source.node_view_span(document, child)
			push!(found, (
				span.start_byte, to_raw(document, span),
				something(Source.attribute(child, "aut"), ""),
				something(Source.attribute(child, "ref"), ""),
			))
		else
			collect_citations!(found, document, child)
		end
	end
	return nothing
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
	return (found, spans)
end


# ===== asserted nodes =====

function asserted_children(
	parents::Vector{Union{Nothing, Int}},
	assertions::Vector{Adjudication.AnchoredNodeAssertion},
)::Tuple{Vector{Vector{Int}}, Vector{Int}}
	children = [Int[] for _ in assertions]
	roots = Int[]
	for index in eachindex(assertions)
		parent = parents[index]
		if isnothing(parent)
			push!(roots, index)
		else
			push!(children[parent], index)
		end
	end
	by_position(index) = assertions[index].span.start_byte
	for group in children
		sort!(group; by = by_position)
	end
	sort!(roots; by = by_position)
	return (children, roots)
end

function build_asserted_node(
	index::Int,
	assertions::Vector{Adjudication.AnchoredNodeAssertion},
	children::Vector{Vector{Int}},
	document::Source.SourceDocument,
	projection::Adjudication.ProjectedView,
)::ResolvedNode
	visible(span::RawSpan)::String = Adjudication.projected_text(
		projection, Source.to_view(document.transform, span),
	)
	assertion = assertions[index]
	form_assertions = filter(item -> item.name == "form", assertion.constituents)
	forms = NodeForm[
		NodeForm(item.span, visible(item.span), item.value) for item in form_assertions
	]
	gloss_index = findfirst(item -> item.name == "gloss", assertion.constituents)
	gloss = isnothing(gloss_index) ? nothing : assertion.constituents[gloss_index].span
	separator_form = isempty(forms) ?
		nothing : last(sort(forms; by = item -> item.span.end_byte)).span
	constituents = NodeConstituent[
		NodeConstituent(item.name, item.span, visible(item.span), item.value)
		for item in assertion.constituents
	]
	return ResolvedNode(
		Source.anchor_id(assertion.span),
		assertion.node_type,
		assertion.span,
		nothing,
		isempty(forms) ? nothing : form_value(first(forms)),
		forms,
		constituents,
		separator_between(document, separator_form, gloss),
		isnothing(gloss) ? Inline[] : Inline[TextRun(visible(gloss), gloss)],
		Qualification[],
		Citation[],
		ResolvedNode[
			build_asserted_node(child, assertions, children, document, projection)
			for child in children[index]
		],
	)
end

function asserted_nodes(
	document::Source.SourceDocument,
	state::AdjudicationState,
	block::Census.SourceBlock,
)::Tuple{Vector{ResolvedNode}, Vector{ViewSpan}}
	assertions = structural_assertions(state, block)
	isnothing(structural_conflict(assertions)) || return (ResolvedNode[], ViewSpan[])
	parents = geometric_parent_indices(assertions)
	(children, roots) = asserted_children(parents, assertions)
	node = Adjudication.element_at(document, block.view_span)
	projection = Adjudication.project(document, node)
	spans = ViewSpan[
		Source.to_view(document.transform, assertion.span) for assertion in assertions
	]
	nodes = ResolvedNode[
		build_asserted_node(index, assertions, children, document, projection)
		for index in roots
	]
	return (nodes, spans)
end

"""
    separator_between(document, form, gloss)

The raw material lying between two adjacent constituents. Littré separates a sub-lemma's
form from its gloss with punctuation that sits in neither span, so without this the
comma in `Avaler des poires d'angoisse, subir des mortifications` is unreconstructible
downstream.
"""
function separator_between(
	document::Source.SourceDocument,
	form::Union{Nothing, RawSpan},
	gloss::Union{Nothing, RawSpan},
)::Union{Nothing, String}
	(isnothing(form) || isnothing(gloss)) && return nothing
	gloss.start_byte > form.end_byte || return nothing
	between = strip(Source.slice(
		document.raw_text, RawSpan(form.file, form.end_byte, gloss.start_byte),
	))
	isempty(between) && return nothing
	# markup here is attached by containment, not presented as a separator
	occursin('<', between) && return nothing
	return String(between)
end


# ===== resolving a block =====

function resolve_block(
	harness::Adjudication.Harness, state::AdjudicationState, block::Census.SourceBlock,
	resolution::Dict{Int, CitationAnaphora}, references::CrossReferenceIndex,
)::ResolvedNode
	document = harness.documents[block.raw_span.file]
	node = Adjudication.element_at(document, block.view_span)

	(resolved, reason) = closure(state, block)
	isempty(reason) || record_review!(state, block, reason)

	(qualifications, marker_spans) = qualification_markers(document, node)
	(bare_qualifications, bare_marker_spans) =
		bare_qualification_markers(document, state, block)
	append!(qualifications, bare_qualifications)
	append!(marker_spans, bare_marker_spans)
	(quotations, citation_spans) = citations(document, node, resolution, references)
	(asserted, asserted_spans) = asserted_nodes(document, state, block)
	children = ResolvedNode[
		resolve_block(harness, state, child, resolution, references)
		for child in block.children
	]
	child_spans = ViewSpan[child.view_span for child in block.children]

	# default parentage is laminar containment; an adjudicated scope overrides only that
	qualifications = apply_scopes(state, block, qualifications)
	asserted = ResolvedNode[
		attach_contained(item, qualifications, quotations) for item in asserted
	]
	qualifications = filter(item -> !attaches_to_any(item, asserted), qualifications)
	quotations = filter(item -> !contained_in_any(item.span, asserted), quotations)

	excluded = vcat(marker_spans, citation_spans, asserted_spans, child_spans)
	definition = inline_content(document, node, excluded, references)

	return ResolvedNode(
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


# ===== attaching by containment =====

contained_in_any(span::RawSpan, nodes::Vector{ResolvedNode})::Bool =
	any(node -> Source.covers(node.span, span), nodes)

"""
    apply_scopes(state, block, qualifications)

Rewrite each marker's scope target from any applicable scope adjudication. A marker with
no adjudication keeps `ContainedScope`, which is a stated geometric rule rather than a
guess, so the absence of a record never becomes a claim.
"""
function apply_scopes(
	state::AdjudicationState,
	block::Census.SourceBlock,
	qualifications::Vector{Qualification},
)::Vector{Qualification}
	for pass in Adjudication.scope_passes
		record = sole(records_for(state, block, pass.pass))
		(isnothing(record) || record.outcome != :positive) && continue
		qualifications = Qualification[
			rescope_from(record, qualification) for qualification in qualifications
		]
	end
	return qualifications
end

function rescope_from(
	record::Adjudication.AppliedRecord, qualification::Qualification,
)::Qualification
	for scope in record.scopes
		scope.marker == qualification.span || continue
		return rescope(qualification, AssertedScope(scope.target))
	end
	return qualification
end

function scope_span(qualification::Qualification)::RawSpan
	qualification.scope isa AssertedScope || return qualification.span
	return qualification.scope.target
end

attaches_to(qualification::Qualification, node::ResolvedNode)::Bool =
	Source.covers(node.span, scope_span(qualification))

attaches_to_any(qualification::Qualification, nodes::Vector{ResolvedNode})::Bool =
	any(node -> attaches_to(qualification, node), nodes)

function attach_contained(
	node::ResolvedNode,
	qualifications::Vector{Qualification},
	quotations::Vector{Citation},
)::ResolvedNode
	children = ResolvedNode[
		attach_contained(child, qualifications, quotations) for child in node.children
	]
	attaches_here(item) =
		attaches_to(item, node) && !attaches_to_any(item, children)
	contained_here(item) =
		Source.covers(node.span, item.span) && !contained_in_any(item.span, children)
	return with(
		node;
		qualifications = filter(attaches_here, qualifications),
		citations = filter(contained_here, quotations),
		children,
	)
end

with_children(node::ResolvedNode, children::Vector{ResolvedNode})::ResolvedNode =
	with(node; children)

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
	return with_children(node, children)
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
	return roots
end

"""
    inner_span(document, node)

The parser-view interval between an element's open and close tags. The etymology
segmenter is ported from v0.2 and consumes source markup directly, so it needs the
element's content bytes rather than a projection.
"""
function inner_span(document::Source.SourceDocument, node::XML.FlatNode)::ViewSpan
	span = Source.node_view_span(document, node)
	children = collect(XML.children(node))
	isempty(children) && return ViewSpan(span.file, span.end_byte, span.end_byte)
	first_child = Source.node_view_span(document, first(children))
	last_child = Source.node_view_span(document, last(children))
	return ViewSpan(span.file, first_child.start_byte, last_child.end_byte)
end


# ===== rubrique conventions =====

const etymology_rubrique = "ÉTYMOLOGIE"

# project convention, policed by an output test rather than declared anywhere else
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

# names a position in the entry header, so it has no entry in the table above
const header_note_type = "header"

const rubrique_headings = Dict(
	"PROVERBE" => "Proverbe.",
	"PROVERBES" => "Proverbes.",
)

rubrique_heading(name::AbstractString) = get(rubrique_headings, name, nothing)

# committed patterns with counted residue; unmatched lead text stays prose
const century_pattern = r"^(?:\(\*\)\s*)?([IVXLC]+)e\.?\s+s\.$"
const century_first_lead_pattern =
	r"^\s*((?:\(\*\)\s*)?([IVXLC]+)e\.?\s+s\.)(?:\s*(Ajoutez\s*:))?"
const supplement_first_lead_pattern =
	r"^\s*(Ajoutez\s*:)(?:\s*((?:\(\*\)\s*)?([IVXLC]+)e\.?\s+s\.))?"
const supplement_label = "supplement"

const date_range_label = "dateRange"


# ===== century headers =====

const roman_values = Dict('I' => 1, 'V' => 5, 'X' => 10, 'L' => 50, 'C' => 100)

function roman_value(numeral::AbstractString)::Union{Nothing, Int}
	total = 0
	previous = 0
	for character in reverse(numeral)
		value = get(roman_values, character, nothing)
		isnothing(value) && return nothing
		total += value < previous ? -value : value
		previous = max(previous, value)
	end
	1 <= total <= 20 || return nothing
	return total
end

"""
    century_range(text)

The half-open Gregorian years a printed century header covers, as `(not_before,
not_after)`, or `nothing` when the header does not parse. `XVIe s.` is 1501–1600: the
ordinal names the century, not the years.
"""
function century_years(numeral::AbstractString)
	century = roman_value(numeral)
	isnothing(century) && return nothing
	return ((century - 1) * 100 + 1, century * 100)
end

function century_range(text::AbstractString)
	found = match(century_pattern, text)
	isnothing(found) && return nothing
	return century_years(found.captures[1])
end

function lead_capture_span(
	span::ViewSpan, found::RegexMatch, capture_index::Int,
)::Union{Nothing, ViewSpan}
	offset = found.offsets[capture_index]
	offset < 1 && return nothing
	printed = found.captures[capture_index]
	isnothing(printed) && return nothing
	start_byte = span.start_byte + offset - 1
	return ViewSpan(span.file, start_byte, start_byte + ncodeunits(printed))
end

normalized_lead_text(text::AbstractString)::String =
	strip(replace(text, r"\s+" => " "))

function historique_lead(
	document::Source.SourceDocument, nodes::Vector{XML.FlatNode},
)::Tuple{Vector{RubriqueLabel}, Vector{ViewSpan}}
	isempty(nodes) && return (RubriqueLabel[], ViewSpan[])
	first_node = first(nodes)
	XML.nodetype(first_node) == XML.Text || return (RubriqueLabel[], ViewSpan[])
	span = Source.node_view_span(document, first_node)
	text = String(Source.slice(document.parser_view, span))
	found = match(century_first_lead_pattern, text)
	century_first = !isnothing(found)
	if !century_first
		found = match(supplement_first_lead_pattern, text)
	end
	isnothing(found) && return (RubriqueLabel[], ViewSpan[])

	labels = RubriqueLabel[]
	excluded = ViewSpan[]
	function printed_at(capture_index::Int)
		view_span = lead_capture_span(span, found, capture_index)
		isnothing(view_span) && return nothing
		text = String(Source.slice(document.parser_view, view_span))
		return (normalized_lead_text(text), view_span)
	end
	function push_supplement!(capture_index::Int)
		located = printed_at(capture_index)
		isnothing(located) && return nothing
		(printed, view_span) = located
		raw_span = to_raw(document, view_span)
		push!(labels, RubriqueLabel(
			supplement_label, printed, nothing, nothing, raw_span,
		))
		push!(excluded, view_span)
		return nothing
	end
	function push_date_range!(capture_index::Int, numeral_index::Int)
		located = printed_at(capture_index)
		isnothing(located) && return nothing
		years = century_years(found.captures[numeral_index])
		isnothing(years) && return nothing
		(printed, view_span) = located
		raw_span = to_raw(document, view_span)
		push!(labels, RubriqueLabel(
			date_range_label, printed, years[1], years[2], raw_span,
		))
		push!(excluded, view_span)
		return nothing
	end

	if century_first
		push_date_range!(1, 2)
		push_supplement!(3)
	else
		push_supplement!(1)
		push_date_range!(2, 3)
	end
	return (labels, excluded)
end


# ===== rubrique content =====

function projected_citation_offset(
	projection::Adjudication.ProjectedView, citation::ViewSpan,
)::Int
	positions = Int[
		segment.projected_end for segment in projection.segments
		if !segment.synthetic && segment.view_end <= citation.start_byte
	]
	isempty(positions) && return 1
	return maximum(positions)
end

function attach_projected_citations(
	document::Source.SourceDocument,
	block::Census.SourceBlock,
	nodes::Vector{ResolvedNode},
	quotations::Vector{Citation},
	citation_spans::Vector{ViewSpan},
)::Vector{ResolvedNode}
	isempty(nodes) && return nodes
	element = Adjudication.element_at(document, block.view_span)
	projection = Adjudication.project(document, element)
	flat = ResolvedNode[]
	visit(items) = for node in items
		push!(flat, node)
		visit(node.children)
	end
	visit(nodes)
	projected = Dict{String, Adjudication.ProjectedSpan}()
	for node in flat
		view_span = Source.to_view(document.transform, node.span)
		span = Adjudication.to_projected(projection, view_span)
		isnothing(span) || (projected[node.node_id] = span)
	end
	assigned = Dict{String, Vector{Citation}}()
	for (quotation, citation_span) in zip(quotations, citation_spans)
		offset = projected_citation_offset(projection, citation_span)
		function holds_offset(node)
			haskey(projected, node.node_id) || return false
			span = projected[node.node_id]
			return span.start_byte <= offset <= span.end_byte
		end
		candidates = filter(holds_offset, flat)
		isempty(candidates) && continue
		target = first(sort(candidates; by = node -> length(projected[node.node_id])))
		push!(get!(assigned, target.node_id, Citation[]), quotation)
	end
	function rewrite(node::ResolvedNode)::ResolvedNode
		children = ResolvedNode[rewrite(child) for child in node.children]
		citations = copy(node.citations)
		seen = Set(Adjudication.anchor_key(citation.span) for citation in citations)
		for citation in get(assigned, node.node_id, Citation[])
			key = Adjudication.anchor_key(citation.span)
			key in seen && continue
			push!(citations, citation)
			push!(seen, key)
		end
		sort!(citations; by = citation -> citation.span.start_byte)
		return with(node; citations, children)
	end
	return ResolvedNode[rewrite(node) for node in nodes]
end

function resolve_rubrique_block_nodes(
	harness::Adjudication.Harness, state::AdjudicationState, block::Census.SourceBlock,
	resolution::Dict{Int, CitationAnaphora}, references::CrossReferenceIndex,
)::Vector{ResolvedNode}
	document = harness.documents[block.raw_span.file]
	node = Adjudication.element_at(document, block.view_span)
	conflict = structural_conflict(structural_assertions(state, block))
	isnothing(conflict) ||
		record_review!(state, block, "structural conflict: $(conflict)")
	(qualifications, _) = qualification_markers(document, node)
	(bare_qualifications, _) = bare_qualification_markers(document, state, block)
	append!(qualifications, bare_qualifications)
	(quotations, citation_spans) = citations(document, node, resolution, references)
	(asserted, _) = asserted_nodes(document, state, block)
	children = ResolvedNode[]
	for child in block.children
		append!(children, resolve_rubrique_block_nodes(
			harness, state, child, resolution, references,
		))
	end
	qualifications = apply_scopes(state, block, qualifications)
	asserted = ResolvedNode[
		attach_contained(item, qualifications, quotations) for item in asserted
	]
	asserted = attach_projected_citations(
		document, block, asserted, quotations, citation_spans,
	)
	return merge_source_children(asserted, children)
end

function rubrique_semantic_nodes(
	harness::Adjudication.Harness,
	state::AdjudicationState,
	rubrique::Census.SourceRubrique,
	resolution::Dict{Int, CitationAnaphora},
	references::CrossReferenceIndex,
)::Vector{ResolvedNode}
	nodes = ResolvedNode[]
	for block in rubrique.blocks
		append!(nodes, resolve_rubrique_block_nodes(
			harness, state, block, resolution, references,
		))
	end
	sort!(nodes; by = node -> node.span.start_byte)
	return nodes
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
	return (views, spans)
end

function split_rubrique_content(
	content::Vector{Inline}, separators::Vector{RawSpan},
)::Vector{Vector{Inline}}
	isempty(content) && return Vector{Inline}[]
	groups = Vector{Inline}[Inline[first(content)]]
	previous = first(content).span
	for item in Iterators.drop(content, 1)
		span = item.span
		between(separator) =
			previous.end_byte <= separator.start_byte &&
			separator.end_byte <= span.start_byte
		cut = any(between, separators)
		cut && push!(groups, Inline[])
		push!(last(groups), item)
		previous = span
	end
	return groups
end

rubrique_item_span(item::RubriqueLabel)::RawSpan = item.span
rubrique_item_span(item::RubriqueCitation)::RawSpan = item.citation.span
rubrique_item_span(item::RubriqueProse)::RawSpan = item.span
rubrique_item_span(item::RubriqueNode)::RawSpan = item.node.span

function resolve_rubrique(
	harness::Adjudication.Harness,
	state::AdjudicationState,
	rubrique::Census.SourceRubrique,
	resolution::Dict{Int, CitationAnaphora},
	references::CrossReferenceIndex,
	findings::Vector{ReviewFinding},
	headword::AbstractString,
)::ResolvedRubrique
	document = harness.documents[rubrique.raw_span.file]
	node = Adjudication.element_at(document, rubrique.view_span)
	items = RubriqueItem[]
	etymology = AnchoredEtymSegment[]
	semantic_nodes = rubrique_semantic_nodes(
		harness, state, rubrique, resolution, references,
	)
	(excluded, semantic_spans) = semantic_exclusions(document, semantic_nodes)
	conventions = conventions_for(rubrique.name)
	if rubrique.name == etymology_rubrique
		for child in XML.children(node)
			XML.nodetype(child) == XML.Element || continue
			XML.tag(child) in ("indent", "variante") || continue
			append!(etymology, segment_paragraph(document, child, references, headword))
		end
		if !isempty(semantic_nodes)
			outside_semantics(segment) =
				!any(span -> Source.covers(span, segment.span), semantic_spans)
			etymology = filter(outside_semantics, etymology)
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
	return ResolvedRubrique(
		rubrique.name, rubrique.raw_span, rubrique.parent_id, items, etymology,
	)
end

function rubrique_items(
	document::Source.SourceDocument,
	node::XML.FlatNode,
	rubrique::Census.SourceRubrique,
	conventions,
	resolution::Dict{Int, CitationAnaphora},
	references::CrossReferenceIndex,
	findings::Vector{ReviewFinding};
	excluded::Vector{ViewSpan} = ViewSpan[],
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
		content = inline_from(
			document, pending, references; excluded = vcat(excluded, lead_excluded),
		)
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
			if leading && isempty(labels) && !isnothing(range)
				push!(items, RubriqueLabel(
					date_range_label, String(text), range[1], range[2], span,
				))
			elseif !isempty(text)
				push!(items, RubriqueProse(group, span))
				if leading && isempty(labels) && rubrique.name == "HISTORIQUE"
					push!(findings, ReviewFinding(
						"century_unrecognized", String(first(text, 60)), span,
					))
				end
			end
		end
		return nothing
	end

	for child in XML.children(node)
		name = XML.nodetype(child) == XML.Element ? XML.tag(child) : ""
		if name == "cit"
			flush!()
			leading = false
			span = Source.node_view_span(document, child)
			carved(span, excluded) && continue
			citation = build_citation(document, child, span, resolution, references)
			push!(items, RubriqueCitation(citation, conventions.subtype))
		elseif name == "indent" || name == "variante"
			flush!()
			leading = false
			child_span = Source.node_view_span(document, child)
			child_excluded = ViewSpan[
				span for span in excluded if !Source.covers(span, child_span)
			]
			append!(items, rubrique_items(
				document, child, rubrique, conventions, resolution, references,
				findings; excluded = child_excluded, semantic_spans,
			))
		else
			push!(pending, child)
		end
	end
	flush!()
	return items
end

"""
    carry_date_range(items)

Attach the most recent century header to each following citation. Items are already in
source order, so the header printed over a group of attestations reaches every member of
that group and stops at the next header.
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
	return carried
end

function segment_paragraph(
	document::Source.SourceDocument,
	node::XML.FlatNode,
	references::CrossReferenceIndex,
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
			to_raw(document, ViewSpan(
				inner.file,
				inner.start_byte + first(range) - 1,
				inner.start_byte + last(range),
			))
		end
		resolved = resolve_segment(segment, references)
		push!(anchored, AnchoredEtymSegment(resolved, span, block))
	end
	return anchored
end

carries_text(text::AbstractString)::Bool =
	any(character -> isletter(character) || isdigit(character), text)

const printed_form = r"[A-ZÀ-ÞŒÆ]{2,}"


# ===== entry header =====

"""
    qualifying_natures(document, header)

How many of the entete's `<nature>` elements qualify the headword itself. The first
always does. A later one does only if nothing since the one before announces a second
headword form, which the source announces in one of two ways: the form printed in
capitals, as in `ACCORDÉ … ACCORDÉE (a-kordée) <nature>s. f.</nature>`, or a further
`<prononciation>`, as in `COBÆA ou COBÉE`. Intervening prose alone does not demote a
label — TARGUER prints its conjugation between `v. a.` and `v. réfl.` and both describe
the headword.
"""
function qualifying_natures(document::Source.SourceDocument, header::XML.FlatNode)::Int
	qualifying = 0
	second_form = false
	for child in XML.children(header)
		nodetype = XML.nodetype(child)
		if nodetype == XML.Text
			text = Source.slice(
				document.parser_view, Source.node_view_span(document, child),
			)
			if occursin(printed_form, text)
				second_form = true
			end
		elseif nodetype == XML.Element
			name = XML.tag(child)
			if name == "nature"
				qualifying > 0 && second_form && return qualifying
				qualifying += 1
				second_form = false
			elseif name == "prononciation" ||
					occursin(printed_form, collapse_inline(document, child))
				second_form = true
			end
		end
	end
	return qualifying
end

function entry_grammar(
	document::Source.SourceDocument, node::XML.FlatNode,
)::Vector{Qualification}
	header = Source.element_children(node, "entete")
	isempty(header) && return Qualification[]
	qualifications = Qualification[]
	natures = Source.element_children(first(header), "nature")
	for nature in natures[1:qualifying_natures(document, first(header))]
		span = to_raw(document, Source.node_view_span(document, nature))
		content = collapse_inline(document, nature)
		append!(qualifications, route_qualifications(content, span))
	end
	return qualifications
end

"""
    entry_header(document, node, references)

The entete material that is neither the entry's pronunciation nor a label qualifying it,
as one note per contiguous run. The first `<prononciation>` and the qualifying
`<nature>` elements are the boundaries; everything between them — loose text, an
`<indent>`, a cross-reference, and the pronunciation and label of any further headword
form — belongs to the run it sits in. A run that prints no letter or digit is separator
punctuation and carries nothing.
"""
function entry_header(
	document::Source.SourceDocument,
	node::XML.FlatNode,
	references::CrossReferenceIndex,
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
		isempty(content) && return nothing
		carries_text(plain_text(content)) || return nothing
		push!(notes, HeaderNote(content, RawSpan(
			first(content).span.file,
			first(content).span.start_byte,
			last(content).span.end_byte,
		)))
		return nothing
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
	return notes
end

function entry_pronunciation(
	document::Source.SourceDocument, node::XML.FlatNode,
)::Union{Nothing, String}
	header = Source.element_children(node, "entete")
	isempty(header) && return nothing
	spoken = Source.element_children(first(header), "prononciation")
	isempty(spoken) && return nothing
	content = collapse_inline(document, first(spoken))
	isempty(content) && return nothing
	return content
end


# ===== resolving an entry =====

function resolve_entry(
	harness::Adjudication.Harness, state::AdjudicationState, entry::Census.SourceEntry,
	references::CrossReferenceIndex, findings::Vector{ReviewFinding},
)::ResolvedEntry
	document = harness.documents[entry.raw_span.file]
	node = Adjudication.element_at(document, entry.view_span)
	resolution = author_resolution(document, node)
	return ResolvedEntry(
		entry.source_id,
		entry.headword,
		entry.homograph,
		entry.raw_span,
		entry_pronunciation(document, node),
		entry_grammar(document, node),
		entry_header(document, node, references),
		ResolvedNode[
			resolve_block(harness, state, block, resolution, references)
			for block in entry.blocks if !in_entete(block.kind)
		],
		ResolvedRubrique[
			resolve_rubrique(
				harness, state, rubrique, resolution, references, findings,
				entry.headword,
			)
			for rubrique in entry.rubriques
		],
	)
end

in_entete(kind::Census.BlockKind)::Bool =
	kind isa Census.EnteteNature || kind isa Census.EnteteIndent

function entry_citations(entry::ResolvedEntry)::Vector{Citation}
	found = Citation[]
	gather(nodes) = for node in nodes
		append!(found, node.citations)
		gather(node.children)
	end
	gather(entry.nodes)
	for rubrique in entry.rubriques, item in rubrique.items
		item isa RubriqueNode || continue
		gather(ResolvedNode[item.node])
	end
	return found
end

function all_entry_citations(entry::ResolvedEntry)::Vector{Citation}
	found = entry_citations(entry)
	for rubrique in entry.rubriques, item in rubrique.items
		item isa RubriqueCitation || continue
		push!(found, item.citation)
	end
	return found
end


# ===== coverage and review =====

function coverage(
	harness::Adjudication.Harness,
	state::AdjudicationState,
	pass::Adjudication.PassDefinition,
)::PassCoverage
	population = Adjudication.eligible(pass, harness.corpus)
	examined = Adjudication.AppliedRecord[]
	for block in population
		record = sole(records_for(state, block, pass.pass))
		isnothing(record) || push!(examined, record)
	end
	return PassCoverage(
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
		for rubrique in entry.rubriques, item in rubrique.items
			item isa RubriqueNode || continue
			visit(ResolvedNode[item.node])
		end
	end
	return nothing
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
		isnothing(progress) || progress(document.file, length(resolved), elapsed)
	end
	check_node_identity(entries)
	unresolved_authors = ReviewFinding[
		ReviewFinding(
			"author_unresolved", "ID. with no antecedent in the entry", citation.span,
		)
		for entry in entries for citation in all_entry_citations(entry)
		if citation.resolution == :unresolved && isnothing(citation.author_antecedent)
	]
	unresolved_references = ReviewFinding[
		ReviewFinding(
			"reference_unresolved", "ib. with no antecedent in the entry", citation.span,
		)
		for entry in entries for citation in all_entry_citations(entry)
		if citation.reference_resolution == :unresolved
	]
	suspects = ReviewFinding[
		ReviewFinding("etymology_suspect", anchored.segment.token, anchored.span)
		for entry in entries for rubrique in entry.rubriques
		for anchored in rubrique.etymology if anchored.segment isa EtymSuspect
	]
	unsegmented = ReviewFinding[
		ReviewFinding(
			"etymology_unsegmented", String(anchored.segment.fallback), anchored.span,
		)
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
	return ResolvedCorpus(entries, review, PassCoverage[
		coverage(harness, state, pass) for pass in Adjudication.current_passes
	])
end
