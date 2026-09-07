struct PassDefinition
	pass::String
	pass_version::Int
	node_type::Union{Nothing, NodeType}
	population::String
	population_version::Int
	projection::String
	projection_version::Int
	exhaustive_extraction::Bool
	question::String
end

const sublemma_pass = PassDefinition(
	"sublemma", 1, SubLemma(), "structural_blocks", 2,
	block_text_projection, block_text_version, true,
	"Does this material introduce a sub-lemma: a multiword unit presented under the lemma with its own sense material?",
)

const qualification_scope_pass = PassDefinition(
	"qualification_scope", 1, nothing, "qualification_blocks", 2,
	block_text_projection, block_text_version, false,
	"Does any qualification marker in this material govern something other than the block that contains it?",
)

const bare_qualification_pass = PassDefinition(
	"bare_qualification", 1, nothing, "qualification_blocks", 2,
	block_text_projection, block_text_version, false,
	"Does this material contain a qualification marker printed as bare prose rather than explicit markup, and if so, what material does it govern?",
)

const voice_variant_pass = PassDefinition(
	"voice_variant", 1, VoiceVariant(), "structural_blocks", 2,
	block_text_projection, block_text_version, true,
	"Does this material introduce a separately form-bearing pronominal or reflexive variant of the current lemma, rather than merely state a grammatical construction or usage?",
)

const current_passes = (
	sublemma_pass, voice_variant_pass,
	qualification_scope_pass, bare_qualification_pass,
)

const structural_passes = filter(pass -> !isnothing(pass.node_type), current_passes)
const scope_passes = filter(pass -> isnothing(pass.node_type), current_passes)

function pass_definition(name::AbstractString)::Union{Nothing, PassDefinition}
	index = findfirst(pass -> pass.pass == name, current_passes)
	isnothing(index) && return nothing
	return current_passes[index]
end

in_structural_population(::Census.Indent) = true
in_structural_population(::Census.Variante) = true
in_structural_population(::Census.ResumeIndent) = false
in_structural_population(::Census.ResumeVariante) = false
in_structural_population(::Census.RubriqueIndent) = true
in_structural_population(::Census.RubriqueVariante) = true
in_structural_population(::Census.RubriqueDirect) = true
in_structural_population(::Census.EnteteIndent) = false
in_structural_population(::Census.EnteteNature) = false

in_qualification_population(::Census.Indent) = true
in_qualification_population(::Census.Variante) = true
in_qualification_population(::Census.ResumeIndent) = false
in_qualification_population(::Census.ResumeVariante) = false
in_qualification_population(::Census.RubriqueIndent) = true
in_qualification_population(::Census.RubriqueVariante) = true
in_qualification_population(::Census.RubriqueDirect) = true
in_qualification_population(::Census.EnteteIndent) = false
in_qualification_population(::Census.EnteteNature) = false

const structural_blocks_population = "structural_blocks"
const qualification_blocks_population = "qualification_blocks"

function population_predicate(name::AbstractString)
	name == structural_blocks_population && return in_structural_population
	name == qualification_blocks_population && return in_qualification_population
	return error("unknown population $(name)")
end

function eligible(
	pass::PassDefinition, corpus::Census.CorpusCensus,
)::Vector{Census.SourceBlock}
	admits = population_predicate(pass.population)
	return filter(block -> admits(block.kind), Census.all_blocks(corpus))
end

struct ContextItem
	role::String
	text::String
end

struct SurfaceMarker
	kind::String
	span::ProjectedSpan
	source::RawSpan
	text::String
end

struct AdjudicationItem
	item_id::String
	block::Census.SourceBlock
	projection::ProjectedView
	context::Vector{ContextItem}
	markers::Vector{SurfaceMarker}
end

struct FormReading
	selection::String
	value::Union{Nothing, String}
end

FormReading(selection::AbstractString) = FormReading(String(selection), nothing)

struct FormSelection
	node::String
	forms::Vector{FormReading}
	gloss::Union{Nothing, String}
	function FormSelection(
		node::AbstractString, forms::Vector{FormReading}, gloss = nothing,
	)
		return new(String(node), forms, isnothing(gloss) ? nothing : String(gloss))
	end
end

FormSelection(node::AbstractString, form::AbstractString, gloss = nothing) =
	FormSelection(node, FormReading[FormReading(form)], gloss)

FormSelection(node::AbstractString, forms::Vector{<:AbstractString}, gloss = nothing) =
	FormSelection(node, FormReading[FormReading(form) for form in forms], gloss)

struct ScopeSelection
	marker::String
	target::String
end

struct Decision
	outcome::Symbol
	exhaustive::Bool
	selections::Vector{FormSelection}
	scopes::Vector{ScopeSelection}
	residuals::Vector{String}
	notes::String
end

function Decision(
	outcome::Symbol;
	exhaustive = false,
	selections = FormSelection[],
	scopes = ScopeSelection[],
	residuals = String[],
	notes = "",
)
	return Decision(outcome, exhaustive, selections, scopes, residuals, notes)
end

const rejection_categories = (
	"schema_violation",
	"ineligible_target",
	"unmappable_selection",
	"structural_conflict",
	"constituent_escapes_node",
	"residual_overlaps_node",
	"residuals_overlap",
	"incomplete_partition",
	"not_a_marker",
	"scope_contains_marker",
)

struct ReviewItem <: Exception
	item_id::String
	pass::String
	category::String
	detail::String
	function ReviewItem(item_id, pass, category, detail)
		if category ∉ rejection_categories 
			error("unknown rejection category $(repr(category))")
		end
		return new(item_id, pass, category, detail)
	end
end

function Base.showerror(io::IO, item::ReviewItem)
	label = "review item $(item.item_id) ($(item.pass)/$(item.category))"
	return print(io, "$(label): $(item.detail)")
end

reject(item::AdjudicationItem, pass::PassDefinition, category, reason) =
	throw(ReviewItem(item.item_id, pass.pass, category, reason))

const SurfaceIndex = Dict{Tuple{String, String}, Vector{Census.SourceBlock}}

struct PassIndex
	fingerprint::Vector{Tuple{String, Float64, Int}}
	by_anchor::Dict{Tuple{String, Int, Int}, ExaminationRecord}
	unanchored::Vector{ExaminationRecord}
end

mutable struct Harness
	documents::Dict{String, Source.SourceDocument}
	corpus::Census.CorpusCensus
	blocks::Dict{Tuple{String, Int, Int}, Census.SourceBlock}
	store::Store
	surface_indices::Dict{String, SurfaceIndex}
	record_indices::Dict{String, PassIndex}
end

anchor_key(span::RawSpan) = (span.file, span.start_byte, span.end_byte)

function Harness(
	documents::Vector{Source.SourceDocument}, corpus::Census.CorpusCensus, store::Store,
)
	return Harness(
		Dict(document.file => document for document in documents),
		corpus,
		Dict(
			anchor_key(block.raw_span) => block for block in Census.all_blocks(corpus)
		),
		store,
		Dict{String, SurfaceIndex}(),
		Dict{String, PassIndex}(),
	)
end

function validate_store(harness::Harness)::Symbol
	directories = store_pass_directories(harness.store)
	isempty(directories) && return :empty
	known = Set(pass.pass for pass in current_passes)
	unknown = filter(directory -> !(directory in known), directories)
	if !isempty(unknown)
		reason = "store contains records for undeclared pass $(join(unknown, ", "))"
		throw(StoreIntegrityError(reason))
	end
	return :valid
end

document_for(harness::Harness, block::Census.SourceBlock)::Source.SourceDocument =
	harness.documents[block.raw_span.file]

const element_at = Source.element_at

function citation_context(document::Source.SourceDocument, node::XML.FlatNode)
	items = ContextItem[]
	for child in XML.children(node)
		XML.nodetype(child) == XML.Element || continue
		XML.tag(child) == "cit" || continue
		push!(items, ContextItem("citation", project(document, child).text))
	end
	return items
end

function surface_markers(
	document::Source.SourceDocument, node::XML.FlatNode, projection::ProjectedView,
)
	markers = SurfaceMarker[]
	for child in XML.children(node)
		XML.nodetype(child) == XML.Element || continue
		kind = XML.tag(child)
		kind in ("semantique", "nature") || continue
		view = Source.node_view_span(document, child)
		span = to_projected(projection, view)
		isnothing(span) && continue
		(raw, _) = Source.node_raw_span(document, child)
		push!(markers, SurfaceMarker(kind, span, raw, projected_text(projection, span)))
	end
	return markers
end

function adjudication_item(
	harness::Harness, block::Census.SourceBlock, item_id::AbstractString,
)
	document = document_for(harness, block)
	node = element_at(document, block.view_span)
	projection = project(document, node)
	return AdjudicationItem(
		String(item_id),
		block,
		projection,
		citation_context(document, node),
		surface_markers(document, node, projection),
	)
end

function present(harness::Harness, pass::PassDefinition, block::Census.SourceBlock)
	population_predicate(pass.population)(block.kind) ||
		throw(ReviewItem("", pass.pass, "ineligible_target", string(block.raw_span)))
	return adjudication_item(harness, block, string(uuid4()))
end

function write_surface_part(io::IO, label::AbstractString, text::AbstractString)
	print(io, ncodeunits(label), ':', label, ':', ncodeunits(text), ':')
	write(io, text)
	write(io, '\n')
	return nothing
end

function surface_text(item::AdjudicationItem)
	buffer = IOBuffer()
	write_surface_part(buffer, "kind", Census.kind_name(item.block.kind))
	write_surface_part(buffer, "target", item.projection.text)
	for marker in item.markers
		write_surface_part(
			buffer,
			"marker:$(marker.kind):$(marker.span.start_byte):$(marker.span.end_byte)",
			marker.text,
		)
	end
	for context in item.context
		write_surface_part(buffer, "context:$(context.role)", context.text)
	end
	return String(take!(buffer))
end

surface_sha256(item::AdjudicationItem) = Source.text_sha256(surface_text(item))

struct SurfaceExport
	pass::PassDefinition
	item::AdjudicationItem
end

"""
The classification surface as a producer sees it: everything `surface_sha256` covers,
plus the pass, its question, and the locator and hash a response must quote to be
committed. Nothing here is interpreted on the way back in; the producer answers in text
and `commit!` locates it.
"""
surface_json(pass::PassDefinition, item::AdjudicationItem)::String =
	canonical_json(SurfaceExport(pass, item))

write_json(io::IO, marker::SurfaceMarker) = object(io) do writer
	field!(writer, "kind", marker.kind)
	field!(writer, "span", marker.span)
	field!(writer, "text", marker.text)
end

write_json(io::IO, context::ContextItem) = object(io) do writer
	field!(writer, "role", context.role)
	field!(writer, "text", context.text)
end

write_json(io::IO, surface::SurfaceExport) = object(io) do writer
	item = surface.item
	pass = surface.pass
	field!(writer, "item_id", item.item_id)
	field!(writer, "pass", pass.pass)
	field!(writer, "pass_version", pass.pass_version)
	field!(writer, "question", pass.question)
	field!(writer, "exhaustive_extraction", pass.exhaustive_extraction)
	field!(writer, "source", item.block.raw_span)
	field!(writer, "surface_sha256", surface_sha256(item))
	field!(writer, "kind", Census.kind_name(item.block.kind))
	field!(writer, "target", item.projection.text)
	field!(writer, "markers", item.markers)
	field!(writer, "context", item.context)
end

function resolve_selection(
	item::AdjudicationItem,
	pass::PassDefinition,
	selection::AbstractString,
	label::AbstractString,
)::ProjectedSpan
	try
		return locate_projected(item.projection, selection)
	catch failure
		failure isa SelectionFailure || rethrow()
		reject(item, pass, "unmappable_selection", "$(label): $(failure.reason)")
	end
end

function validate_geometry(
	item::AdjudicationItem, pass::PassDefinition, assertions::Vector{NodeAssertion},
)
	for outer in eachindex(assertions), inner in (outer + 1):lastindex(assertions)
		left = assertions[outer].span
		right = assertions[inner].span
		if left == right
			reject(item, pass, "structural_conflict", "coincident node spans $(left)")
		end
		if !projected_laminar(left, right)
			reject(
				item, pass, "structural_conflict",
				"node spans cross: $(left) and $(right)",
			)
		end
	end
	for assertion in assertions, constituent in assertion.constituents
		if !projected_covers(assertion.span, constituent.span)
			reject(
				item, pass, "constituent_escapes_node",
				"$(constituent.name) lies outside its node",
			)
		end
	end
	for outer in assertions, inner in assertions
		outer === inner && continue
		for constituent in outer.constituents
			if projected_covers(constituent.span, inner.span)
				reject(
					item, pass, "structural_conflict",
					"a node lies inside the $(constituent.name) of another node",
				)
			end
		end
	end
	return nothing
end

function target_block!(
	harness::Harness, record::ExaminationRecord, pass::PassDefinition,
)::Union{Nothing, Census.SourceBlock}
	record.pass_version == pass.pass_version || return nothing
	admits = population_predicate(pass.population)
	exact = get(harness.blocks, anchor_key(record.source), nothing)
	if !isnothing(exact)
		admits(exact.kind) || return nothing
		item = adjudication_item(harness, exact, "")
		surface_sha256(item) == record.surface_sha256 && return exact
		return nothing
	end
	index = get!(harness.surface_indices, pass.pass) do
		built = SurfaceIndex()
		for block in eligible(pass, harness.corpus)
			item = adjudication_item(harness, block, "")
			key = (block.raw_span.file, surface_sha256(item))
			push!(get!(built, key, Census.SourceBlock[]), block)
		end
		return built
	end
	candidates = get(
		index, (record.source.file, record.surface_sha256), Census.SourceBlock[],
	)
	length(candidates) == 1 && return only(candidates)
	return nothing
end

function pass_fingerprint(
	store::Store, pass::AbstractString,
)::Vector{Tuple{String, Float64, Int}}
	directory = pass_directory(store, pass)
	isdir(directory) || return Tuple{String, Float64, Int}[]
	files = filter(file -> endswith(file, ".jsonl"), readdir(directory; join = true))
	return [(basename(file), mtime(file), filesize(file)) for file in sort(files)]
end

function pass_index!(harness::Harness, pass::PassDefinition)::PassIndex
	fingerprint = pass_fingerprint(harness.store, pass.pass)
	cached = get(harness.record_indices, pass.pass, nothing)
	if !isnothing(cached) && cached.fingerprint == fingerprint
		return cached
	end
	by_anchor = Dict{Tuple{String, Int, Int}, ExaminationRecord}()
	unanchored = ExaminationRecord[]
	for record in read_pass(harness.store, pass.pass)
		key = anchor_key(record.source)
		if haskey(harness.blocks, key)
			by_anchor[key] = record
		else
			push!(unanchored, record)
		end
	end
	index = PassIndex(fingerprint, by_anchor, unanchored)
	harness.record_indices[pass.pass] = index
	return index
end

function applicable_record!(
	harness::Harness, block::Census.SourceBlock, pass::PassDefinition,
)::Union{Nothing, ExaminationRecord}
	index = pass_index!(harness, pass)
	candidate = get(index.by_anchor, anchor_key(block.raw_span), nothing)
	if !isnothing(candidate) &&
			target_block!(harness, candidate, pass) == block &&
			check!(harness, candidate) == :valid
		return candidate
	end
	for record in index.unanchored
		target_block!(harness, record, pass) == block || continue
		check!(harness, record) == :valid || continue
		return record
	end
	return nothing
end

function validate_against_store!(
	harness::Harness,
	item::AdjudicationItem,
	pass::PassDefinition,
	assertions::Vector{NodeAssertion},
)
	isempty(assertions) && return nothing
	for other_pass in current_passes
		isnothing(other_pass.node_type) && continue
		other_pass.pass == pass.pass && continue
		record = applicable_record!(harness, item.block, other_pass)
		isnothing(record) && continue
		record.outcome == :positive || continue
		for assertion in assertions, existing in record.assertions
			if assertion.span == existing.span
				reject(
					item, pass, "structural_conflict",
					"coincident node span $(assertion.span) with $(other_pass.pass)",
				)
			end
			if !projected_laminar(assertion.span, existing.span)
				reason = "node span $(assertion.span) crosses " *
					"$(other_pass.pass) span $(existing.span)"
				reject(item, pass, "structural_conflict", reason)
			end
		end
	end
	return nothing
end

function validate_residuals(
	item::AdjudicationItem,
	pass::PassDefinition,
	residuals::Vector{ProjectedSpan},
	assertions::Vector{NodeAssertion},
)
	for residual in residuals, assertion in assertions
		projected_disjoint(residual, assertion.span) ||
			reject(item, pass, "residual_overlaps_node", string(residual))
	end
	for outer in eachindex(residuals), inner in (outer + 1):lastindex(residuals)
		if projected_overlaps(residuals[outer], residuals[inner])
			reject(
				item, pass, "residuals_overlap",
				"$(residuals[outer]) and $(residuals[inner])",
			)
		end
	end
	return nothing
end

function form_pair_error(first_form, second_form)::Union{Nothing, String}
	if first_form.span == second_form.span
		msg = "coincident form spans require distinct editorial values"
		isnothing(first_form.value) && return msg
		isnothing(second_form.value) && return msg
		first_form.value == second_form.value && return msg
		return nothing
	end
	if projected_overlaps(first_form.span, second_form.span)
		return "form spans must be disjoint or coincident readings of one surface span"
	end
	if first_form.span.start_byte > second_form.span.start_byte
		return "disjoint form spans must be supplied in source order"
	end
	return nothing
end

function constituent_shape_error(constituents)::Union{Nothing, String}
	if any(item -> item.name ∉ ("form", "gloss"), constituents)
		return "unknown constituent name"
	end
	glosses = filter(item -> item.name == "gloss", constituents)
	if length(glosses) > 1
		return "a form-bearing node may carry at most one gloss"
	end
	if any(item -> item.name != "form" && !isnothing(item.value), constituents)
		return "only form constituents may carry an editorial value"
	end
	forms = filter(item -> item.name == "form", constituents)
	isempty(forms) && return "a form-bearing node needs at least one form"
	for form in forms
		if !isnothing(form.value) && isempty(strip(form.value))
			return "a form value may not be empty"
		end
	end
	for left in eachindex(forms), right in (left + 1):lastindex(forms)
		pair_error = form_pair_error(forms[left], forms[right])
		isnothing(pair_error) || return pair_error
	end
	return nothing
end

function build_assertions(
	item::AdjudicationItem, pass::PassDefinition, decision::Decision,
)::Vector{NodeAssertion}
	assertions = NodeAssertion[]
	for selection in decision.selections
		span = resolve_selection(item, pass, selection.node, "node")
		if isempty(selection.forms)
			reason = "a form-bearing node needs at least one form"
			reject(item, pass, "schema_violation", reason)
		end
		constituents = Constituent[
			Constituent(
				"form",
				resolve_selection(item, pass, form.selection, "form"),
				form.value,
			)
			for form in selection.forms
		]
		if !isnothing(selection.gloss)
			gloss = resolve_selection(item, pass, selection.gloss, "gloss")
			push!(constituents, Constituent("gloss", gloss))
		end
		geometry_error = constituent_shape_error(constituents)
		if !isnothing(geometry_error)
			reason = geometry_error
			reject(item, pass, "schema_violation", reason)
		end
		if !form_bearing(pass.node_type)
			reason = "$(node_type_name(pass.node_type)) is not form-bearing"
			reject(item, pass, "schema_violation", reason)
		end
		assertion = NodeAssertion(string(uuid4()), pass.node_type, span, constituents)
		push!(assertions, assertion)
	end
	return assertions
end

function marker_for_selection(
	item::AdjudicationItem, selected::ProjectedSpan,
)::Union{Nothing, SurfaceMarker}
	matches = filter(marker -> projected_covers(marker.span, selected), item.markers)
	length(matches) == 1 && return only(matches)
	return nothing
end

is_bare_marker_pass(pass::PassDefinition)::Bool =
	pass.pass == bare_qualification_pass.pass

function valid_scope_marker(
	item::AdjudicationItem, pass::PassDefinition, selected::ProjectedSpan,
)::Bool
	if is_bare_marker_pass(pass)
		return all(marker -> projected_disjoint(marker.span, selected), item.markers)
	end
	return any(marker -> marker.span == selected, item.markers)
end

function selected_marker_span(
	item::AdjudicationItem, pass::PassDefinition, selected::ProjectedSpan,
)::Union{Nothing, ProjectedSpan}
	if is_bare_marker_pass(pass)
		valid_scope_marker(item, pass, selected) || return nothing
		return selected
	end
	marker = marker_for_selection(item, selected)
	isnothing(marker) && return nothing
	return marker.span
end

function build_scopes(
	item::AdjudicationItem, pass::PassDefinition, decision::Decision,
)::Vector{ScopeAssertion}
	scopes = ScopeAssertion[]
	for selection in decision.scopes
		selected = resolve_selection(item, pass, selection.marker, "marker")
		marker_span = selected_marker_span(item, pass, selected)
		if isnothing(marker_span)
			reason = if is_bare_marker_pass(pass)
				"$(repr(selection.marker)) overlaps an explicit qualification marker"
			else
				"$(repr(selection.marker)) is not an unambiguous " *
					"qualification marker in this block"
			end
			reject(item, pass, "not_a_marker", reason)
		end
		# resolution applies the first scope it finds for a marker, so a second
		# target would be accepted here and then silently dropped
		if any(scope -> scope.marker == marker_span, scopes)
			reason = "$(repr(selection.marker)) already governs material in this block"
			reject(item, pass, "schema_violation", reason)
		end
		target = resolve_selection(item, pass, selection.target, "scope target")
		if projected_overlaps(marker_span, target)
			reason = "a marker may not be inside the material it governs"
			reject(item, pass, "scope_contains_marker", reason)
		end
		push!(scopes, ScopeAssertion(marker_span, target))
	end
	return scopes
end

function mark_claimed!(claimed::BitVector, span::ProjectedSpan)
	for position in span.start_byte:(span.end_byte - 1)
		1 <= position <= length(claimed) && (claimed[position] = true)
	end
	return nothing
end

function partition_gap(
	projection::ProjectedView, spans::Vector{ProjectedSpan},
)::Union{Nothing, String}
	claimed = falses(ncodeunits(projection.text))
	for span in spans
		mark_claimed!(claimed, span)
	end
	for segment in projection.segments
		segment.synthetic && continue
		for position in segment.projected_start:(segment.projected_end - 1)
			claimed[position] && continue
			character = projection.text[thisind(projection.text, position)]
			isspace(character) && continue
			stop = min(segment.projected_end, position + 40)
			gap = SubString(
				projection.text,
				thisind(projection.text, position),
				prevind(projection.text, stop),
			)
			return String(strip(gap))
		end
	end
	return nothing
end

function verify_partition(
	item::AdjudicationItem,
	pass::PassDefinition,
	decision::Decision,
	assertions::Vector{NodeAssertion},
	residuals::Vector{ProjectedSpan},
)
	decision.exhaustive || return nothing
	unaccounted = partition_gap(
		item.projection,
		vcat(ProjectedSpan[assertion.span for assertion in assertions], residuals),
	)
	if !isnothing(unaccounted)
		reason = "exhaustive claim leaves $(repr(unaccounted)) unaccounted for"
		reject(item, pass, "incomplete_partition", reason)
	end
	return nothing
end

function validate_decision_shape(
	item::AdjudicationItem, pass::PassDefinition, decision::Decision,
)
	positive = decision.outcome == :positive
	if !positive && (!isempty(decision.selections) || !isempty(decision.scopes))
		reason = "assertions on a non-positive outcome"
		reject(item, pass, "schema_violation", reason)
	end
	if !positive && decision.exhaustive
		reason = "exhaustive claim without a positive outcome"
		reject(item, pass, "schema_violation", reason)
	end
	if decision.exhaustive && !pass.exhaustive_extraction
		reason = "exhaustive claim from a pass that does not perform exhaustive extraction"
		reject(item, pass, "schema_violation", reason)
	end
	if positive && pass.exhaustive_extraction && !decision.exhaustive
		reason = "positive outcome without the exhaustive claim this pass requires"
		reject(item, pass, "schema_violation", reason)
	end
	if positive && isempty(decision.selections) && isempty(decision.scopes)
		reason = "positive outcome with no assertion"
		reject(item, pass, "schema_violation", reason)
	end
	if !isempty(decision.scopes) && !isnothing(pass.node_type)
		reason = "scope assertions from a structural pass"
		reject(item, pass, "schema_violation", reason)
	end
	if !isempty(decision.selections) && isnothing(pass.node_type)
		reason = "node assertions from a pass with no node type"
		reject(item, pass, "schema_violation", reason)
	end
	if !isempty(decision.residuals) && !pass.exhaustive_extraction
		reason = "residuals from a non-exhaustive pass"
		reject(item, pass, "schema_violation", reason)
	end
	return nothing
end

function commit!(
	harness::Harness,
	pass::PassDefinition,
	item::AdjudicationItem,
	decision::Decision;
	decision_procedure::AbstractString,
	decision_reference = nothing,
	now::AbstractString = timestamp(),
)::ExaminationRecord
	if isempty(strip(decision_procedure))
		reject(item, pass, "schema_violation", "record names no decision procedure")
	end
	if decision.outcome ∉ outcomes
		reject(item, pass, "schema_violation", "unknown outcome $(decision.outcome)")
	end
	validate_decision_shape(item, pass, decision)

	assertions = build_assertions(item, pass, decision)
	scopes = build_scopes(item, pass, decision)
	validate_geometry(item, pass, assertions)
	validate_against_store!(harness, item, pass, assertions)
	residuals = ProjectedSpan[
		resolve_selection(item, pass, residual, "residual")
		for residual in decision.residuals
	]
	validate_residuals(item, pass, residuals, assertions)
	verify_partition(item, pass, decision, assertions, residuals)

	return ExaminationRecord(
		string(uuid4()),
		pass.pass,
		pass.pass_version,
		item.block.raw_span,
		surface_sha256(item),
		decision.outcome,
		assertions,
		scopes,
		residuals,
		String(decision_procedure),
		decision_reference,
		now,
		decision.notes,
	)
end

timestamp()::String = Dates.format(Dates.now(Dates.UTC), "yyyy-mm-ddTHH:MM:SSZ")

function valid_projected_span(text::AbstractString, span::ProjectedSpan)::Bool
	span.start_byte >= 1 || return false
	span.end_byte > span.start_byte || return false
	span.end_byte <= ncodeunits(text) + 1 || return false
	thisind(text, span.start_byte) == span.start_byte || return false
	span.end_byte == ncodeunits(text) + 1 && return true
	return thisind(text, span.end_byte) == span.end_byte
end

function validate_record_shape(
	record::ExaminationRecord, pass::PassDefinition, item::AdjudicationItem,
)
	assertions = record.assertions
	residuals = record.residuals
	text = item.projection.text
	pass_name = pass.pass
	record.outcome in outcomes ||
		integrity_error(record, "has unknown outcome $(record.outcome)")
	if record.outcome == :positive
		isempty(assertions) && isempty(record.scopes) &&
			integrity_error(record, "is positive with no assertion")
	else
		isempty(assertions) ||
			integrity_error(record, "has node assertions on a non-positive outcome")
		isempty(record.scopes) ||
			integrity_error(record, "has scope assertions on a non-positive outcome")
		isempty(residuals) ||
			integrity_error(record, "has residuals on a non-positive outcome")
	end
	if isnothing(pass.node_type)
		isempty(assertions) ||
			integrity_error(record, "has node assertions for pass $(pass_name)")
		if !isempty(residuals)
			integrity_error(
				record, "has residuals for non-exhaustive pass $(pass_name)",
			)
		end
	else
		isempty(record.scopes) ||
			integrity_error(record, "has scope assertions for pass $(pass_name)")
		expected_type = typeof(pass.node_type)
		if any(assertion -> typeof(assertion.node_type) != expected_type, assertions)
			integrity_error(record, "has the wrong node type for pass $(pass_name)")
		end
	end
	for assertion in assertions
		valid_projected_span(text, assertion.span) ||
			integrity_error(record, "has an invalid node span $(assertion.span)")
		geometry_error = constituent_shape_error(assertion.constituents)
		isnothing(geometry_error) ||
			integrity_error(record, "has invalid form constituents: $(geometry_error)")
		for constituent in assertion.constituents
			if !valid_projected_span(text, constituent.span)
				integrity_error(
					record, "has an invalid constituent span $(constituent.span)",
				)
			end
			projected_covers(assertion.span, constituent.span) ||
				integrity_error(record, "has a constituent outside its node")
		end
	end
	for outer in eachindex(assertions), inner in (outer + 1):lastindex(assertions)
		left = assertions[outer].span
		right = assertions[inner].span
		left == right && integrity_error(record, "has coincident node spans")
		projected_laminar(left, right) ||
			integrity_error(record, "has crossing node spans")
	end
	for residual in residuals
		valid_projected_span(text, residual) ||
			integrity_error(record, "has an invalid residual span $(residual)")
		all(assertion -> projected_disjoint(residual, assertion.span), assertions) ||
			integrity_error(record, "has a residual overlapping a node")
	end
	for outer in eachindex(residuals), inner in (outer + 1):lastindex(residuals)
		projected_disjoint(residuals[outer], residuals[inner]) ||
			integrity_error(record, "has overlapping residuals")
	end
	for scope in record.scopes
		valid_projected_span(text, scope.marker) ||
			integrity_error(record, "has an invalid scope marker span")
		valid_projected_span(text, scope.target) ||
			integrity_error(record, "has an invalid scope target span")
		projected_disjoint(scope.marker, scope.target) ||
			integrity_error(record, "has an overlapping scope marker and target")
		if !valid_scope_marker(item, pass, scope.marker)
			integrity_error(
				record, "names material that is no longer a valid qualification marker",
			)
		end
	end
	if record.outcome == :positive && pass.exhaustive_extraction
		gap = partition_gap(
			item.projection,
			vcat(ProjectedSpan[assertion.span for assertion in assertions], residuals),
		)
		isnothing(gap) || integrity_error(record, "leaves $(repr(gap)) unaccounted for")
	end
	return nothing
end

function materialize_span(
	document::Source.SourceDocument, projection::ProjectedView, span::ProjectedSpan,
)::RawSpan
	view = to_view(projection, span.start_byte, span.end_byte)
	if isnothing(view)
		error("projected span $(span) maps to no source-visible material")
	end
	(raw, _) = Source.to_raw(document.transform, view)
	Source.validate_span(document.raw_text, raw)
	return raw
end

function materialize_record!(
	harness::Harness, record::ExaminationRecord,
)::Union{Nothing, AppliedRecord}
	pass = pass_definition(record.pass)
	isnothing(pass) && return nothing
	record.pass_version == pass.pass_version || return nothing
	block = target_block!(harness, record, pass)
	isnothing(block) && return nothing
	item = adjudication_item(harness, block, "")
	surface_sha256(item) == record.surface_sha256 || return nothing
	validate_record_shape(record, pass, item)
	document = document_for(harness, block)
	assertions = AnchoredNodeAssertion[
		AnchoredNodeAssertion(
			assertion.node_id,
			assertion.node_type,
			materialize_span(document, item.projection, assertion.span),
			AnchoredConstituent[
				AnchoredConstituent(
					constituent.name,
					materialize_span(document, item.projection, constituent.span),
					constituent.value,
				)
				for constituent in assertion.constituents
			],
		)
		for assertion in record.assertions
	]
	scopes = AnchoredScopeAssertion[]
	for scope in record.scopes
		marker = if is_bare_marker_pass(pass)
			materialize_span(document, item.projection, scope.marker)
		else
			matches = filter(candidate -> candidate.span == scope.marker, item.markers)
			only(matches).source
		end
		target = materialize_span(document, item.projection, scope.target)
		push!(scopes, AnchoredScopeAssertion(marker, target))
	end
	residuals = RawSpan[
		materialize_span(document, item.projection, residual)
		for residual in record.residuals
	]
	return AppliedRecord(
		record.record_id,
		record.pass,
		record.pass_version,
		block.raw_span,
		record.outcome,
		assertions,
		scopes,
		residuals,
	)
end

function check!(harness::Harness, record::ExaminationRecord)::Symbol
	isnothing(materialize_record!(harness, record)) && return :stale
	return :valid
end

applicable(result::Symbol)::Bool = result == :valid
