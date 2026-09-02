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

const current_passes = (sublemma_pass, voice_variant_pass, qualification_scope_pass, bare_qualification_pass)

const structural_passes = filter(pass -> pass.node_type !== nothing, current_passes)
const scope_passes = filter(pass -> pass.node_type === nothing, current_passes)

function pass_definition(name::AbstractString)::Union{Nothing, PassDefinition}
	index = findfirst(pass -> pass.pass == name, current_passes)
	index === nothing ? nothing : current_passes[index]
end

in_structural_population(::Census.Indent) = true
in_structural_population(::Census.Variante) = true
in_structural_population(::Census.ResumeIndent) = false
in_structural_population(::Census.ResumeVariante) = false
in_structural_population(::Census.RubriqueIndent) = true
in_structural_population(::Census.RubriqueVariante) = true
in_structural_population(::Census.RubriqueDirect) = true
in_structural_population(::Census.EnteteNature) = false

in_qualification_population(::Census.Indent) = true
in_qualification_population(::Census.Variante) = true
in_qualification_population(::Census.ResumeIndent) = false
in_qualification_population(::Census.ResumeVariante) = false
in_qualification_population(::Census.RubriqueIndent) = true
in_qualification_population(::Census.RubriqueVariante) = true
in_qualification_population(::Census.RubriqueDirect) = true
in_qualification_population(::Census.EnteteNature) = false

const structural_blocks_population = "structural_blocks"
const qualification_blocks_population = "qualification_blocks"

function population_predicate(name::AbstractString)
	name == structural_blocks_population && return in_structural_population
	name == qualification_blocks_population && return in_qualification_population
	error("unknown population $(name)")
end

function eligible(pass::PassDefinition, corpus::Census.CorpusCensus)::Vector{Census.SourceBlock}
	admits = population_predicate(pass.population)
	filter(block -> admits(block.kind), Census.all_blocks(corpus))
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
end

FormSelection(node::AbstractString, form::AbstractString) =
	FormSelection(String(node), FormReading[FormReading(form)], nothing)
FormSelection(node::AbstractString, form::AbstractString, gloss::Union{Nothing, AbstractString}) =
	FormSelection(String(node), FormReading[FormReading(form)], gloss === nothing ? nothing : String(gloss))
FormSelection(node::AbstractString, forms::Vector{<:AbstractString}) =
	FormSelection(String(node), FormReading[FormReading(form) for form in forms], nothing)
FormSelection(node::AbstractString, forms::Vector{<:AbstractString}, gloss::Union{Nothing, AbstractString}) =
	FormSelection(String(node), FormReading[FormReading(form) for form in forms], gloss === nothing ? nothing : String(gloss))
FormSelection(node::AbstractString, forms::Vector{FormReading}) =
	FormSelection(String(node), forms, nothing)

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

Decision(outcome::Symbol; exhaustive = false, selections = FormSelection[],
	scopes = ScopeSelection[], residuals = String[], notes = "") =
	Decision(outcome, exhaustive, selections, scopes, residuals, notes)

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
		category in rejection_categories || error("unknown rejection category $(repr(category))")
		new(item_id, pass, category, detail)
	end
end

Base.showerror(io::IO, item::ReviewItem) = print(
	io, "review item ", item.item_id, " (", item.pass, "/", item.category, "): ", item.detail,
)

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
	surface_indices::Dict{String, Dict{Tuple{String, String}, Vector{Census.SourceBlock}}}
	record_indices::Dict{String, PassIndex}
end

anchor_key(span::RawSpan) = (span.file, span.start_byte, span.end_byte)

function Harness(documents::Vector{Source.SourceDocument}, corpus::Census.CorpusCensus, store::Store)
	Harness(
		Dict(document.file => document for document in documents),
		corpus,
		Dict(anchor_key(block.raw_span) => block for block in Census.all_blocks(corpus)),
		store,
		Dict{String, Dict{Tuple{String, String}, Vector{Census.SourceBlock}}}(),
		Dict{String, PassIndex}(),
	)
end

function validate_store(harness::Harness)::Symbol
	directories = store_pass_directories(harness.store)
	isempty(directories) && return :empty
	known = Set(pass.pass for pass in current_passes)
	unknown = filter(directory -> !(directory in known), directories)
	isempty(unknown) || throw(StoreIntegrityError(
		"store contains records for undeclared pass $(join(unknown, ", "))",
	))
	:valid
end

document_for(harness::Harness, block::Census.SourceBlock)::Source.SourceDocument =
	harness.documents[block.raw_span.file]

const element_at = Source.element_at

function citation_context(document::Source.SourceDocument, node::XML.FlatNode)::Vector{ContextItem}
	items = ContextItem[]
	for child in XML.children(node)
		XML.nodetype(child) == XML.Element && XML.tag(child) == "cit" || continue
		push!(items, ContextItem("citation", project(document, child).text))
	end
	items
end

function surface_markers(
	document::Source.SourceDocument, node::XML.FlatNode, projection::ProjectedView,
)::Vector{SurfaceMarker}
	markers = SurfaceMarker[]
	for child in XML.children(node)
		XML.nodetype(child) == XML.Element || continue
		kind = XML.tag(child)
		kind in ("semantique", "nature") || continue
		view = Source.node_view_span(document, child)
		span = to_projected(projection, view)
		span === nothing && continue
		(raw, _) = Source.node_raw_span(document, child)
		push!(markers, SurfaceMarker(kind, span, raw, projected_text(projection, span)))
	end
	markers
end

function adjudication_item(
	harness::Harness, block::Census.SourceBlock, item_id::AbstractString,
)::AdjudicationItem
	document = document_for(harness, block)
	node = element_at(document, block.view_span)
	projection = project(document, node)
	AdjudicationItem(
		String(item_id), block, projection, citation_context(document, node),
		surface_markers(document, node, projection),
	)
end

function present(harness::Harness, pass::PassDefinition, block::Census.SourceBlock)::AdjudicationItem
	population_predicate(pass.population)(block.kind) || throw(ReviewItem(
		"", pass.pass, "ineligible_target", string(block.raw_span),
	))
	adjudication_item(harness, block, string(uuid4()))
end

function write_surface_part(io::IO, label::AbstractString, text::AbstractString)
	print(io, ncodeunits(label), ':', label, ':', ncodeunits(text), ':')
	write(io, text)
	write(io, '\n')
	nothing
end

function surface_text(item::AdjudicationItem)::String
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
	String(take!(buffer))
end

surface_sha256(item::AdjudicationItem)::String = Source.text_sha256(surface_text(item))

function resolve_selection(
	item::AdjudicationItem, pass::PassDefinition, selection::AbstractString, label::AbstractString,
)::ProjectedSpan
	try
		locate_projected(item.projection, selection)
	catch failure
		failure isa SelectionFailure || rethrow()
		throw(ReviewItem(item.item_id, pass.pass, "unmappable_selection", "$(label): $(failure.reason)"))
	end
end

function validate_geometry(item::AdjudicationItem, pass::PassDefinition, assertions::Vector{NodeAssertion})
	for outer in eachindex(assertions), inner in (outer + 1):lastindex(assertions)
		left = assertions[outer]
		right = assertions[inner]
		projected_covers(left.span, right.span) && projected_covers(right.span, left.span) && throw(ReviewItem(
			item.item_id, pass.pass, "structural_conflict", "coincident node spans $(left.span)",
		))
		projected_laminar(left.span, right.span) || throw(ReviewItem(
			item.item_id, pass.pass, "structural_conflict", "node spans cross: $(left.span) and $(right.span)",
		))
	end
	for assertion in assertions, constituent in assertion.constituents
		projected_covers(assertion.span, constituent.span) || throw(ReviewItem(
			item.item_id, pass.pass, "constituent_escapes_node",
			"$(constituent.name) lies outside its node",
		))
	end
	for outer in assertions, inner in assertions
		outer === inner && continue
		for constituent in outer.constituents
			projected_covers(constituent.span, inner.span) && throw(ReviewItem(
				item.item_id, pass.pass, "structural_conflict",
				"a node lies inside the $(constituent.name) of another node",
			))
		end
	end
	nothing
end

function target_block(
	harness::Harness, record::ExaminationRecord, pass::PassDefinition,
)::Union{Nothing, Census.SourceBlock}
	record.pass_version == pass.pass_version || return nothing
	admits = population_predicate(pass.population)
	exact = get(harness.blocks, anchor_key(record.source), nothing)
	if exact !== nothing
		admits(exact.kind) || return nothing
		item = adjudication_item(harness, exact, "")
		return surface_sha256(item) == record.surface_sha256 ? exact : nothing
	end
	index = get!(harness.surface_indices, pass.pass) do
		built = Dict{Tuple{String, String}, Vector{Census.SourceBlock}}()
		for block in eligible(pass, harness.corpus)
			item = adjudication_item(harness, block, "")
			key = (block.raw_span.file, surface_sha256(item))
			push!(get!(built, key, Census.SourceBlock[]), block)
		end
		built
	end
	candidates = get(index, (record.source.file, record.surface_sha256), Census.SourceBlock[])
	length(candidates) == 1 ? only(candidates) : nothing
end

function pass_fingerprint(store::Store, pass::AbstractString)::Vector{Tuple{String, Float64, Int}}
	directory = pass_directory(store, pass)
	isdir(directory) && return [
		(basename(path), mtime(path), filesize(path))
		for path in sort(filter(name -> endswith(name, ".jsonl"), readdir(directory; join = true)))
	]
	Tuple{String, Float64, Int}[]
end

function pass_index(harness::Harness, pass::PassDefinition)::PassIndex
	fingerprint = pass_fingerprint(harness.store, pass.pass)
	cached = get(harness.record_indices, pass.pass, nothing)
	cached === nothing || cached.fingerprint != fingerprint || return cached
	by_anchor = Dict{Tuple{String, Int, Int}, ExaminationRecord}()
	unanchored = ExaminationRecord[]
	for record in read_pass(harness.store, pass.pass)
		key = anchor_key(record.source)
		haskey(harness.blocks, key) ? (by_anchor[key] = record) : push!(unanchored, record)
	end
	harness.record_indices[pass.pass] = PassIndex(fingerprint, by_anchor, unanchored)
end

function applicable_record(
	harness::Harness, block::Census.SourceBlock, pass::PassDefinition,
)::Union{Nothing, ExaminationRecord}
	index = pass_index(harness, pass)
	candidate = get(index.by_anchor, anchor_key(block.raw_span), nothing)
	if candidate !== nothing
		target_block(harness, candidate, pass) == block &&
			check(harness, candidate) == :valid && return candidate
	end
	for record in index.unanchored
		target_block(harness, record, pass) == block || continue
		check(harness, record) == :valid || continue
		return record
	end
	nothing
end

function validate_against_store(
	harness::Harness, item::AdjudicationItem, pass::PassDefinition, assertions::Vector{NodeAssertion},
)
	isempty(assertions) && return nothing
	for other_pass in current_passes
		other_pass.node_type === nothing && continue
		other_pass.pass == pass.pass && continue
		record = applicable_record(harness, item.block, other_pass)
		(record === nothing || record.outcome != :positive) && continue
		for assertion in assertions, existing in record.assertions
			projected_covers(assertion.span, existing.span) &&
			projected_covers(existing.span, assertion.span) && throw(ReviewItem(
				item.item_id, pass.pass, "structural_conflict",
				"coincident node span $(assertion.span) with $(other_pass.pass)",
			))
			projected_laminar(assertion.span, existing.span) || throw(ReviewItem(
				item.item_id, pass.pass, "structural_conflict",
				"node span $(assertion.span) crosses $(other_pass.pass) span $(existing.span)",
			))
		end
	end
	nothing
end

function validate_residuals(
	item::AdjudicationItem, pass::PassDefinition,
	residuals::Vector{ProjectedSpan}, assertions::Vector{NodeAssertion},
)
	for residual in residuals
		for assertion in assertions
			projected_disjoint(residual, assertion.span) || throw(ReviewItem(
				item.item_id, pass.pass, "residual_overlaps_node", string(residual),
			))
		end
	end
	for outer in eachindex(residuals), inner in (outer + 1):lastindex(residuals)
		projected_disjoint(residuals[outer], residuals[inner]) || throw(ReviewItem(
			item.item_id, pass.pass, "residuals_overlap", "$(residuals[outer]) and $(residuals[inner])",
		))
	end
	nothing
end


function constituent_shape_error(constituents)::Union{Nothing, String}
	all(item -> item.name in ("form", "gloss"), constituents) ||
		return "unknown constituent name"
	glosses = filter(item -> item.name == "gloss", constituents)
	length(glosses) <= 1 || return "a form-bearing node may carry at most one gloss"
	all(item -> item.name == "form" || item.value === nothing, constituents) ||
		return "only form constituents may carry an editorial value"
	forms = filter(item -> item.name == "form", constituents)
	isempty(forms) && return "a form-bearing node needs at least one form"
	for form in forms
		if form.value !== nothing && isempty(strip(form.value))
			return "a form value may not be empty"
		end
	end
	for left in eachindex(forms), right in (left + 1):lastindex(forms)
		first_form = forms[left]
		second_form = forms[right]
		same = projected_covers(first_form.span, second_form.span) &&
			projected_covers(second_form.span, first_form.span)
		if same
			(first_form.value !== nothing && second_form.value !== nothing &&
				first_form.value != second_form.value) ||
				return "coincident form spans require distinct editorial values"
		elseif !projected_disjoint(first_form.span, second_form.span)
			return "form spans must be disjoint or coincident readings of one surface span"
		elseif first_form.span.start_byte > second_form.span.start_byte
			return "disjoint form spans must be supplied in source order"
		end
	end
	nothing
end

function build_assertions(
	item::AdjudicationItem, pass::PassDefinition, decision::Decision,
)::Vector{NodeAssertion}
	assertions = NodeAssertion[]
	for selection in decision.selections
		span = resolve_selection(item, pass, selection.node, "node")
		isempty(selection.forms) && throw(ReviewItem(
			item.item_id, pass.pass, "schema_violation", "a form-bearing node needs at least one form",
		))
		constituents = Constituent[
			Constituent(
				"form",
				resolve_selection(item, pass, form.selection, "form"),
				form.value,
			)
			for form in selection.forms
		]
		selection.gloss === nothing || push!(
			constituents,
			Constituent("gloss", resolve_selection(item, pass, selection.gloss, "gloss")),
		)
		geometry_error = constituent_shape_error(constituents)
		geometry_error === nothing || throw(ReviewItem(
			item.item_id, pass.pass, "schema_violation", geometry_error,
		))
		form_bearing(pass.node_type) || throw(ReviewItem(
			item.item_id, pass.pass, "schema_violation",
			"$(node_type_name(pass.node_type)) is not form-bearing",
		))
		push!(assertions, NodeAssertion(string(uuid4()), pass.node_type, span, constituents))
	end
	assertions
end

function marker_for_selection(
	item::AdjudicationItem, selected::ProjectedSpan,
)::Union{Nothing, SurfaceMarker}
	matches = filter(marker -> projected_covers(marker.span, selected), item.markers)
	length(matches) == 1 ? only(matches) : nothing
end

is_bare_marker_pass(pass::PassDefinition)::Bool = pass.pass == bare_qualification_pass.pass

function selected_marker_span(
	item::AdjudicationItem, pass::PassDefinition, selected::ProjectedSpan,
)::Union{Nothing, ProjectedSpan}
	if is_bare_marker_pass(pass)
		all(marker -> projected_disjoint(marker.span, selected), item.markers) || return nothing
		return selected
	end
	marker = marker_for_selection(item, selected)
	marker === nothing ? nothing : marker.span
end

function valid_scope_marker(
	item::AdjudicationItem, pass::PassDefinition, selected::ProjectedSpan,
)::Bool
	if is_bare_marker_pass(pass)
		return all(marker -> projected_disjoint(marker.span, selected), item.markers)
	end
	any(marker -> marker.span == selected, item.markers)
end

function build_scopes(
	item::AdjudicationItem, pass::PassDefinition, decision::Decision,
)::Vector{ScopeAssertion}
	scopes = ScopeAssertion[]
	for selection in decision.scopes
		selected = resolve_selection(item, pass, selection.marker, "marker")
		marker_span = selected_marker_span(item, pass, selected)
		marker_span === nothing && throw(ReviewItem(
			item.item_id, pass.pass, "not_a_marker",
			is_bare_marker_pass(pass) ?
				"$(repr(selection.marker)) overlaps an explicit qualification marker" :
				"$(repr(selection.marker)) is not an unambiguous qualification marker in this block",
		))
		# Resolution applies the first scope it finds for a marker, so a second target would be
		# accepted here and then silently dropped.
		any(scope -> scope.marker == marker_span, scopes) && throw(ReviewItem(
			item.item_id, pass.pass, "schema_violation",
			"$(repr(selection.marker)) already governs material in this block",
		))
		target = resolve_selection(item, pass, selection.target, "scope target")
		projected_disjoint(marker_span, target) || throw(ReviewItem(
			item.item_id, pass.pass, "scope_contains_marker",
			"a marker may not be inside the material it governs",
		))
		push!(scopes, ScopeAssertion(marker_span, target))
	end
	scopes
end

function mark_claimed!(claimed::BitVector, span::ProjectedSpan)
	for position in span.start_byte:(span.end_byte - 1)
		1 <= position <= length(claimed) && (claimed[position] = true)
	end
	nothing
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
			return String(strip(SubString(
				projection.text,
				thisind(projection.text, position),
				prevind(projection.text, stop),
			)))
		end
	end
	nothing
end

function verify_partition(
	item::AdjudicationItem, pass::PassDefinition, decision::Decision,
	assertions::Vector{NodeAssertion}, residuals::Vector{ProjectedSpan},
)
	decision.exhaustive || return nothing
	unaccounted = partition_gap(
		item.projection,
		vcat(ProjectedSpan[assertion.span for assertion in assertions], residuals),
	)
	unaccounted === nothing || throw(ReviewItem(
		item.item_id, pass.pass, "incomplete_partition",
		"exhaustive claim leaves $(repr(unaccounted)) unaccounted for",
	))
	nothing
end

function commit(
	harness::Harness, pass::PassDefinition, item::AdjudicationItem, decision::Decision;
	decision_procedure::AbstractString, decision_reference = nothing,
	now::AbstractString = timestamp(),
)::ExaminationRecord
	isempty(strip(decision_procedure)) && throw(ReviewItem(
		item.item_id, pass.pass, "schema_violation", "record names no decision procedure",
	))
	decision.outcome in outcomes || throw(ReviewItem(
		item.item_id, pass.pass, "schema_violation", "unknown outcome $(decision.outcome)",
	))
	decision.outcome == :positive || (isempty(decision.selections) && isempty(decision.scopes)) ||
		throw(ReviewItem(item.item_id, pass.pass, "schema_violation", "assertions on a non-positive outcome"))
	decision.outcome == :positive || !decision.exhaustive || throw(ReviewItem(
		item.item_id, pass.pass, "schema_violation", "exhaustive claim without a positive outcome",
	))
	decision.exhaustive && !pass.exhaustive_extraction && throw(ReviewItem(
		item.item_id, pass.pass, "schema_violation",
		"exhaustive claim from a pass that does not perform exhaustive extraction",
	))
	decision.outcome != :positive || !pass.exhaustive_extraction || decision.exhaustive ||
		throw(ReviewItem(
			item.item_id, pass.pass, "schema_violation",
			"positive outcome without the exhaustive claim this pass requires",
		))
	decision.outcome != :positive || !isempty(decision.selections) || !isempty(decision.scopes) ||
		throw(ReviewItem(item.item_id, pass.pass, "schema_violation", "positive outcome with no assertion"))
	isempty(decision.scopes) || pass.node_type === nothing || throw(ReviewItem(
		item.item_id, pass.pass, "schema_violation", "scope assertions from a structural pass",
	))
	isempty(decision.selections) || pass.node_type !== nothing || throw(ReviewItem(
		item.item_id, pass.pass, "schema_violation", "node assertions from a pass with no node type",
	))
	isempty(decision.residuals) || pass.exhaustive_extraction || throw(ReviewItem(
		item.item_id, pass.pass, "schema_violation", "residuals from a non-exhaustive pass",
	))

	assertions = build_assertions(item, pass, decision)
	scopes = build_scopes(item, pass, decision)
	validate_geometry(item, pass, assertions)
	validate_against_store(harness, item, pass, assertions)
	residuals = ProjectedSpan[
		resolve_selection(item, pass, residual, "residual") for residual in decision.residuals
	]
	validate_residuals(item, pass, residuals, assertions)
	verify_partition(item, pass, decision, assertions, residuals)

	ExaminationRecord(
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
	span.end_byte == ncodeunits(text) + 1 || thisind(text, span.end_byte) == span.end_byte
end

function validate_record_shape(
	record::ExaminationRecord, pass::PassDefinition, item::AdjudicationItem,
)
	record.outcome in outcomes || throw(StoreIntegrityError(
		"record $(record.record_id) has unknown outcome $(record.outcome)",
	))
	if record.outcome == :positive
		isempty(record.assertions) && isempty(record.scopes) && throw(StoreIntegrityError(
			"record $(record.record_id) is positive with no assertion",
		))
	else
		isempty(record.assertions) || throw(StoreIntegrityError(
			"record $(record.record_id) has node assertions on a non-positive outcome",
		))
		isempty(record.scopes) || throw(StoreIntegrityError(
			"record $(record.record_id) has scope assertions on a non-positive outcome",
		))
		isempty(record.residuals) || throw(StoreIntegrityError(
			"record $(record.record_id) has residuals on a non-positive outcome",
		))
	end
	if pass.node_type === nothing
		isempty(record.assertions) || throw(StoreIntegrityError(
			"record $(record.record_id) has node assertions for pass $(pass.pass)",
		))
		isempty(record.residuals) || throw(StoreIntegrityError(
			"record $(record.record_id) has residuals for non-exhaustive pass $(pass.pass)",
		))
	else
		isempty(record.scopes) || throw(StoreIntegrityError(
			"record $(record.record_id) has scope assertions for pass $(pass.pass)",
		))
		all(assertion -> typeof(assertion.node_type) == typeof(pass.node_type), record.assertions) ||
			throw(StoreIntegrityError("record $(record.record_id) has the wrong node type for pass $(pass.pass)"))
	end
	for assertion in record.assertions
		valid_projected_span(item.projection.text, assertion.span) || throw(StoreIntegrityError(
			"record $(record.record_id) has an invalid node span $(assertion.span)",
		))
		geometry_error = constituent_shape_error(assertion.constituents)
		geometry_error === nothing || throw(StoreIntegrityError(
			"record $(record.record_id) has invalid form constituents: $(geometry_error)",
		))
		for constituent in assertion.constituents
			valid_projected_span(item.projection.text, constituent.span) || throw(StoreIntegrityError(
				"record $(record.record_id) has an invalid constituent span $(constituent.span)",
			))
			projected_covers(assertion.span, constituent.span) || throw(StoreIntegrityError(
				"record $(record.record_id) has a constituent outside its node",
			))
		end
	end
	for outer in eachindex(record.assertions), inner in (outer + 1):lastindex(record.assertions)
		left = record.assertions[outer].span
		right = record.assertions[inner].span
		projected_covers(left, right) && projected_covers(right, left) && throw(StoreIntegrityError(
			"record $(record.record_id) has coincident node spans",
		))
		projected_laminar(left, right) || throw(StoreIntegrityError(
			"record $(record.record_id) has crossing node spans",
		))
	end
	for residual in record.residuals
		valid_projected_span(item.projection.text, residual) || throw(StoreIntegrityError(
			"record $(record.record_id) has an invalid residual span $(residual)",
		))
		all(assertion -> projected_disjoint(residual, assertion.span), record.assertions) ||
			throw(StoreIntegrityError("record $(record.record_id) has a residual overlapping a node"))
	end
	for outer in eachindex(record.residuals), inner in (outer + 1):lastindex(record.residuals)
		projected_disjoint(record.residuals[outer], record.residuals[inner]) || throw(StoreIntegrityError(
			"record $(record.record_id) has overlapping residuals",
		))
	end
	for scope in record.scopes
		valid_projected_span(item.projection.text, scope.marker) || throw(StoreIntegrityError(
			"record $(record.record_id) has an invalid scope marker span",
		))
		valid_projected_span(item.projection.text, scope.target) || throw(StoreIntegrityError(
			"record $(record.record_id) has an invalid scope target span",
		))
		projected_disjoint(scope.marker, scope.target) || throw(StoreIntegrityError(
			"record $(record.record_id) has an overlapping scope marker and target",
		))
		valid_scope_marker(item, pass, scope.marker) || throw(StoreIntegrityError(
			"record $(record.record_id) names material that is no longer a valid qualification marker",
		))
	end
	if record.outcome == :positive && pass.exhaustive_extraction
		gap = partition_gap(
			item.projection,
			vcat(ProjectedSpan[assertion.span for assertion in record.assertions], record.residuals),
		)
		gap === nothing || throw(StoreIntegrityError(
			"record $(record.record_id) leaves $(repr(gap)) unaccounted for",
		))
	end
	nothing
end

function materialize_span(
	document::Source.SourceDocument, projection::ProjectedView, span::ProjectedSpan,
)::RawSpan
	view = to_view(projection, span.start_byte, span.end_byte)
	view === nothing && error("projected span $(span) maps to no source-visible material")
	(raw, _) = Source.to_raw(document.transform, view)
	Source.validate_span(document.raw_text, raw)
	raw
end

function materialize_record(
	harness::Harness, record::ExaminationRecord,
)::Union{Nothing, AppliedRecord}
	pass = pass_definition(record.pass)
	pass === nothing && return nothing
	record.pass_version == pass.pass_version || return nothing
	block = target_block(harness, record, pass)
	block === nothing && return nothing
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
			only(filter(candidate -> candidate.span == scope.marker, item.markers)).source
		end
		push!(scopes, AnchoredScopeAssertion(
			marker,
			materialize_span(document, item.projection, scope.target),
		))
	end
	residuals = RawSpan[
		materialize_span(document, item.projection, residual) for residual in record.residuals
	]
	AppliedRecord(
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

check(harness::Harness, record::ExaminationRecord)::Symbol =
	materialize_record(harness, record) === nothing ? :stale : :valid

applicable(result::Symbol)::Bool = result == :valid
