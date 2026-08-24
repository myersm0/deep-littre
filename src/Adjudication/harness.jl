"""
The harness is the controlled boundary between an adjudicator and the store. The adjudicator
decides semantic questions against projected text; the harness owns source identity, coordinate
translation, hashes, ids, validation, and canonical writing.
"""
struct PassDefinition
	pass::String
	pass_version::Int
	population::String
	population_version::Int
	projection::String
	projection_version::Int
end

const sublemma_pass = PassDefinition(
	"sublemma", 1, "structural_blocks", 1, block_text_projection, block_text_version,
)

const voice_variant_pass = PassDefinition(
	"voice_variant", 1, "structural_blocks", 1, block_text_projection, block_text_version,
)

# Structural population version 1. Every census kind is named, so a new kind fails loudly here
# rather than being silently admitted or silently dropped.
in_structural_population(::Census.Indent) = true
in_structural_population(::Census.Variante) = true
in_structural_population(::Census.ResumeVariante) = false
in_structural_population(::Census.RubriqueIndent) = false
in_structural_population(::Census.RubriqueVariante) = false
in_structural_population(::Census.EnteteNature) = false

function eligible(::PassDefinition, corpus::Census.CorpusCensus)::Vector{Census.SourceBlock}
	filter(block -> in_structural_population(block.kind), Census.all_blocks(corpus))
end

struct AdjudicationItem
	item_id::String
	block::Census.SourceBlock
	projection::ProjectedView
	context::Vector{ContextReference}
end

struct SubLemmaSelection
	node::String
	form::String
	gloss::Union{Nothing, String}
end

SubLemmaSelection(node, form) = SubLemmaSelection(node, form, nothing)

"""
A structural decision expressed entirely in projected text. `exhaustive` asserts that the listed
sub-lemmas are all of them within the target, which is what entitles the harness to materialize
negatives on the residual spans.
"""
struct Decision
	outcome::Symbol
	exhaustive::Bool
	selections::Vector{SubLemmaSelection}
	residuals::Vector{String}
	notes::String
end

Decision(outcome::Symbol; exhaustive = false, selections = SubLemmaSelection[],
	residuals = String[], notes = "") =
	Decision(outcome, exhaustive, selections, residuals, notes)

struct ReviewItem <: Exception
	item_id::String
	pass::String
	category::String
	detail::String
end

Base.showerror(io::IO, item::ReviewItem) = print(
	io, "review item ", item.item_id, " (", item.pass, "/", item.category, "): ", item.detail,
)

struct Harness
	documents::Dict{String, Source.SourceDocument}
	corpus::Census.CorpusCensus
	blocks::Dict{Tuple{String, Int, Int}, Census.SourceBlock}
	store::Store
end

anchor_key(span::RawSpan) = (span.file, span.start_byte, span.end_byte)

function Harness(documents::Vector{Source.SourceDocument}, corpus::Census.CorpusCensus, store::Store)
	Harness(
		Dict(document.file => document for document in documents),
		corpus,
		Dict(anchor_key(block.raw_span) => block for block in Census.all_blocks(corpus)),
		store,
	)
end

document_for(harness::Harness, block::Census.SourceBlock)::Source.SourceDocument =
	harness.documents[block.raw_span.file]

function element_at(document::Source.SourceDocument, span::ViewSpan)
	function search(node)
		for child in XML.children(node)
			XML.nodetype(child) == XML.Element || continue
			range = XML.sourcespan(child)
			start_byte = first(range)
			end_byte = nextind(document.parser_view, last(range))
			start_byte == span.start_byte && end_byte == span.end_byte && return child
			if start_byte <= span.start_byte && end_byte >= span.end_byte
				result = search(child)
				result === nothing || return result
			end
		end
		nothing
	end
	result = search(document.document)
	result === nothing && error("no element at $(span)")
	result
end

"""
	present(harness, pass, block; context_roles)

Render the versioned target projection for one eligible block, plus any citation context the pass
permits. Context does not enlarge the adjudicated span but does participate in validity.
"""
function present(harness::Harness, pass::PassDefinition, block::Census.SourceBlock)::AdjudicationItem
	document = document_for(harness, block)
	node = element_at(document, block.view_span)
	projection = project(document, node)
	AdjudicationItem(string(uuid4()), block, projection, citation_context(harness, document, node))
end

function citation_context(
	harness::Harness, document::Source.SourceDocument, node::XML.FlatNode,
)::Vector{ContextReference}
	references = ContextReference[]
	for child in XML.children(node)
		XML.nodetype(child) == XML.Element && XML.tag(child) == "cit" || continue
		(raw, _) = Source.node_raw_span(document, child)
		projection = project(document, child)
		push!(references, ContextReference(
			raw,
			Source.raw_sha256(document, raw),
			projection.name,
			projection.version,
			view_sha256(projection),
			"citation",
		))
	end
	references
end

function resolve_selection(
	harness::Harness, item::AdjudicationItem, pass::PassDefinition,
	selection::AbstractString, label::AbstractString,
)::RawSpan
	document = document_for(harness, item.block)
	view = try
		locate(item.projection, selection)
	catch failure
		failure isa SelectionFailure ||
			rethrow()
		throw(ReviewItem(item.item_id, pass.pass, "unmappable_selection", "$(label): $(failure.reason)"))
	end
	(raw, _) = Source.to_raw(document.transform, view)
	Source.validate_span(document.raw_text, raw)
	Source.covers(item.block.raw_span, raw) ||
		throw(ReviewItem(item.item_id, pass.pass, "selection_escapes_block", label))
	raw
end

function validate_geometry(item::AdjudicationItem, pass::PassDefinition, assertions::Vector{NodeAssertion})
	for outer in eachindex(assertions), inner in (outer + 1):lastindex(assertions)
		Source.laminar(assertions[outer].span, assertions[inner].span) ||
			throw(ReviewItem(item.item_id, pass.pass, "structural_conflict",
				"node spans cross: $(assertions[outer].span) and $(assertions[inner].span)"))
	end
	for assertion in assertions
		for constituent in assertion.constituents
			Source.covers(assertion.span, constituent.span) ||
				throw(ReviewItem(item.item_id, pass.pass, "constituent_escapes_node",
					"$(constituent.name) lies outside its node"))
		end
	end
	nothing
end

function validate_residuals(
	item::AdjudicationItem, pass::PassDefinition,
	residuals::Vector{RawSpan}, assertions::Vector{NodeAssertion},
)
	for residual in residuals
		Source.covers(item.block.raw_span, residual) ||
			throw(ReviewItem(item.item_id, pass.pass, "residual_escapes_block", string(residual)))
		for assertion in assertions
			Source.disjoint(residual, assertion.span) ||
				throw(ReviewItem(item.item_id, pass.pass, "residual_overlaps_node", string(residual)))
		end
	end
	nothing
end

function build_assertions(
	harness::Harness, item::AdjudicationItem, pass::PassDefinition, decision::Decision,
)::Vector{NodeAssertion}
	assertions = NodeAssertion[]
	for selection in decision.selections
		span = resolve_selection(harness, item, pass, selection.node, "node")
		constituents = Constituent[
			Constituent("form", resolve_selection(harness, item, pass, selection.form, "form")),
		]
		selection.gloss === nothing || push!(constituents, Constituent(
			"gloss", resolve_selection(harness, item, pass, selection.gloss, "gloss"),
		))
		push!(assertions, NodeAssertion(string(uuid4()), SubLemma(), span, nothing, constituents))
	end
	assertions
end

"""
	commit(harness, pass, item, decision; method, adjudicator, model)

Validate a decision and mint the anchored record. Nothing about source identity is supplied by the
adjudicator: spans come from projected selections, hashes and ids from repository data.
"""
function commit(
	harness::Harness, pass::PassDefinition, item::AdjudicationItem, decision::Decision;
	method::Symbol = :human, adjudicator::AbstractString = "", model = nothing,
	llm_input_sha256 = nothing, now::AbstractString = timestamp(),
)::ExaminationRecord
	decision.outcome in outcomes ||
		throw(ReviewItem(item.item_id, pass.pass, "schema_violation", "unknown outcome $(decision.outcome)"))
	method in methods ||
		throw(ReviewItem(item.item_id, pass.pass, "schema_violation", "unknown method $(method)"))
	decision.outcome == :positive || isempty(decision.selections) ||
		throw(ReviewItem(item.item_id, pass.pass, "schema_violation", "assertions on a non-positive outcome"))
	decision.outcome == :positive || !decision.exhaustive ||
		throw(ReviewItem(item.item_id, pass.pass, "schema_violation", "exhaustive claim without a positive outcome"))
	decision.outcome != :positive || !isempty(decision.selections) ||
		throw(ReviewItem(item.item_id, pass.pass, "schema_violation", "positive outcome with no assertion"))

	document = document_for(harness, item.block)
	assertions = build_assertions(harness, item, pass, decision)
	validate_geometry(item, pass, assertions)
	residuals = RawSpan[
		resolve_selection(harness, item, pass, residual, "residual") for residual in decision.residuals
	]
	validate_residuals(item, pass, residuals, assertions)

	ExaminationRecord(
		string(uuid4()),
		pass.pass,
		pass.pass_version,
		pass.population,
		pass.population_version,
		item.block.raw_span,
		Source.raw_sha256(document, item.block.raw_span),
		item.block.synthetic_boundary,
		item.projection.name,
		item.projection.version,
		view_sha256(item.projection),
		item.context,
		llm_input_sha256,
		decision.outcome,
		decision.exhaustive,
		assertions,
		residuals,
		method,
		adjudicator,
		model,
		now,
		decision.notes,
	)
end

timestamp()::String = Dates.format(Dates.now(Dates.UTC), "yyyy-mm-ddTHH:MM:SSZ")

"""
	check(harness, record)

Apply the two independent target checks. A raw-anchor mismatch is a corpus/store integrity
failure; a view mismatch quarantines the record. Neither ever falls through to a heuristic answer.
"""
function check(harness::Harness, record::ExaminationRecord)::Symbol
	document = get(harness.documents, record.source.file, nothing)
	document === nothing && return :raw_mismatch
	Source.covers(RawSpan(record.source.file, 1, ncodeunits(document.raw_text) + 1), record.source) ||
		return :raw_mismatch
	Source.raw_sha256(document, record.source) == record.raw_sha256 || return :raw_mismatch
	block = get(harness.blocks, anchor_key(record.source), nothing)
	block === nothing && return :missing_block
	view_sha256(project(document, element_at(document, block.view_span))) == record.view_sha256 ||
		return :view_mismatch
	for reference in record.context
		Source.raw_sha256(document, reference.span) == reference.raw_sha256 || return :stale_context
	end
	:valid
end

"""
Build-time disposition of a check result. A raw-anchor failure is a store/corpus integrity
failure and aborts; everything else quarantines the record and produces a review item.
"""
fatal(result::Symbol)::Bool = result == :raw_mismatch
applicable(result::Symbol)::Bool = result == :valid
