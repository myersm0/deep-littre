"""
The harness is the controlled boundary between an adjudicator and the store. The adjudicator
decides semantic questions against projected text; the harness owns source identity, coordinate
translation, hashes, ids, validation, and canonical writing.
"""
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
	"sublemma", 1, SubLemma(), "structural_blocks", 1,
	block_text_projection, block_text_version, true,
	"Does this material introduce a sub-lemma: a multiword unit presented under the lemma with \
	its own sense material?",
)

# Scope is never merely "on the block": a qualification's target is explicit. Containment is the
# deterministic default and needs no adjudication; this pass records departures from it, and a
# negative outcome is the positive statement that every marker here scopes as containment implies.
const qualification_scope_pass = PassDefinition(
	"qualification_scope", 1, nothing, "qualification_blocks", 1,
	block_text_projection, block_text_version, false,
	"Does any qualification marker in this material govern something other than the block that \
	contains it?",
)

# Narrow by question, not by population. A statement that a verb takes a reflexive construction is
# a grammatical property; only a separately presented form-bearing alternant is a node.
const voice_variant_pass = PassDefinition(
	"voice_variant", 1, VoiceVariant(), "structural_blocks", 1,
	block_text_projection, block_text_version, true,
	"Does this material introduce a separately form-bearing pronominal or reflexive variant of the \
	current lemma, rather than merely state a grammatical construction or usage?",
)

const current_passes = (sublemma_pass, voice_variant_pass, qualification_scope_pass)

function pass_definition(name::AbstractString)::Union{Nothing, PassDefinition}
	index = findfirst(pass -> pass.pass == name, current_passes)
	index === nothing ? nothing : current_passes[index]
end

# Structural population version 1: main-definition blocks only. Every census kind is named, so a
# new kind fails loudly here rather than being silently admitted or silently dropped. Résumé
# material summarizes senses represented elsewhere in the entry and is not itself sense material.
in_structural_population(::Census.Indent) = true
in_structural_population(::Census.Variante) = true
in_structural_population(::Census.ResumeIndent) = false
in_structural_population(::Census.ResumeVariante) = false
in_structural_population(::Census.RubriqueIndent) = false
in_structural_population(::Census.RubriqueVariante) = false
in_structural_population(::Census.EnteteNature) = false

# Qualification population version 1. Identical in extent to the structural population today, but
# named separately because it answers a different question: qualification markers also occur in
# rubrique-internal blocks, and widening to reach them should be a population version bump rather
# than a change to what the structural passes mean.
in_qualification_population(::Census.Indent) = true
in_qualification_population(::Census.Variante) = true
in_qualification_population(::Census.ResumeIndent) = false
in_qualification_population(::Census.ResumeVariante) = false
in_qualification_population(::Census.RubriqueIndent) = false
in_qualification_population(::Census.RubriqueVariante) = false
in_qualification_population(::Census.EnteteNature) = false

const structural_blocks_population = "structural_blocks"
const qualification_blocks_population = "qualification_blocks"

function population_predicate(name::AbstractString)
	name == structural_blocks_population && return in_structural_population
	name == qualification_blocks_population && return in_qualification_population
	error("unknown population $(name)")
end

const populations = (
	(name = structural_blocks_population, version = 1),
	(name = qualification_blocks_population, version = 1),
)

population_version(name::AbstractString)::Int =
	populations[findfirst(entry -> entry.name == name, populations)].version

function eligible(pass::PassDefinition, corpus::Census.CorpusCensus)::Vector{Census.SourceBlock}
	admits = population_predicate(pass.population)
	filter(block -> admits(block.kind), Census.all_blocks(corpus))
end

function population_manifest(name::AbstractString)::PopulationManifest
	admits = population_predicate(name)
	included = String[]
	excluded = String[]
	for kind in Census.block_kinds
		push!(admits(kind) ? included : excluded, Census.kind_name(kind))
	end
	PopulationManifest(population_version(name), included, excluded)
end


struct AdjudicationItem
	item_id::String
	block::Census.SourceBlock
	projection::ProjectedView
	context::Vector{ContextReference}
end

"""
A selection for a form-bearing node type. `node` bounds the whole alternant; `form` and `gloss` are
constituent sub-spans of it. All three are projected text, never coordinates.
"""
struct FormSelection
	node::String
	form::String
	gloss::Union{Nothing, String}
end

FormSelection(node, form) = FormSelection(node, form, nothing)

"""
A scope selection names the printed marker and the material it governs, both as projected text.
"""
struct ScopeSelection
	marker::String
	target::String
end

"""
A decision expressed entirely in projected text. `exhaustive` asserts that the listed assertions
are all of them within the target, which is what entitles the harness to materialize negatives on
the residual spans.
"""
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

function manifest_text(harness::Harness)::String
	buffer = IOBuffer()
	println(buffer, "# Generated by the authoring harness. The versions in force when this store was")
	println(buffer, "# written, for reading it later and for migrating it. Each record carries its own")
	println(buffer, "# versions and hashes, and those are what gate whether a verdict applies.")
	println(buffer)
	println(buffer, "structural_alternative_set_version = $(structural_alternative_set_version)")
	println(buffer, "closure_protocol_version = $(closure_protocol_version)")
	println(buffer)
	println(buffer, "[projections.$(block_text_projection)]")
	println(buffer, "version = $(block_text_version)")
	println(buffer, "description = \"$(block_text_description)\"")
	for entry in populations
		population = population_manifest(entry.name)
		println(buffer)
		println(buffer, "[populations.$(entry.name)]")
		println(buffer, "version = $(population.version)")
		println(buffer, "includes = [", join(("\"$(value)\"" for value in population.includes), ", "), "]")
		println(buffer, "excludes = [", join(("\"$(value)\"" for value in population.excludes), ", "), "]")
	end
	for pass in current_passes
		println(buffer)
		println(buffer, "[passes.$(pass.pass)]")
		println(buffer, "pass_version = $(pass.pass_version)")
		println(buffer, "population = \"$(pass.population)\"")
		println(buffer, "population_version = $(pass.population_version)")
		println(buffer, "projection = \"$(pass.projection)\"")
		println(buffer, "projection_version = $(pass.projection_version)")
		println(buffer, "exhaustive_extraction = $(pass.exhaustive_extraction)")
	end
	String(take!(buffer))
end

function initialize_store!(harness::Harness)
	store_has_records(harness.store) && throw(StoreIntegrityError(
		"cannot initialize manifest for nonempty store $(harness.store.root)",
	))
	isfile(manifest_path(harness.store)) && throw(StoreIntegrityError(
		"store $(harness.store.root) already has manifest.toml",
	))
	mkpath(harness.store.root)
	replace_atomically(manifest_path(harness.store), manifest_text(harness))
	nothing
end

"""
	validate_store(harness)

The store-wide gates, which are deliberately few: only claims with no per-record equivalent, since
`check` already gates each record and a mismatch there costs one verdict rather than the store.
"""
function validate_store(harness::Harness)::Symbol
	manifest = read_manifest(harness.store)
	has_records = store_has_records(harness.store)
	manifest === nothing && !has_records && return :empty
	manifest === nothing && throw(StoreIntegrityError(
		"nonempty store $(harness.store.root) has no manifest.toml",
	))
	errors = String[]
	manifest.structural_alternative_set_version == structural_alternative_set_version || push!(
		errors,
		"structural alternative-set version mismatch: manifest=$(manifest.structural_alternative_set_version), current=$(structural_alternative_set_version)",
	)
	manifest.closure_protocol_version == closure_protocol_version || push!(
		errors,
		"closure protocol version mismatch: manifest=$(manifest.closure_protocol_version), current=$(closure_protocol_version)",
	)
	known = Set(pass.pass for pass in current_passes)
	for directory in store_pass_directories(harness.store)
		directory in known ||
			push!(errors, "store contains records for undeclared pass $(directory)")
	end
	isempty(errors) || throw(StoreIntegrityError(join(errors, "; ")))
	:valid
end


document_for(harness::Harness, block::Census.SourceBlock)::Source.SourceDocument =
	harness.documents[block.raw_span.file]

const element_at = Source.element_at

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
		push!(references, ContextReference(raw, "citation"))
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
		left = assertions[outer]
		right = assertions[inner]
		Source.covers(left.span, right.span) && Source.covers(right.span, left.span) && throw(ReviewItem(
			item.item_id, pass.pass, "structural_conflict",
			"coincident node spans $(left.span)",
		))
		Source.laminar(left.span, right.span) ||
			throw(ReviewItem(item.item_id, pass.pass, "structural_conflict",
				"node spans cross: $(left.span) and $(right.span)"))
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

function latest_applicable_record(
	harness::Harness, block::Census.SourceBlock, pass::PassDefinition,
)::Union{Nothing, ExaminationRecord}
	for record in read_pass(harness.store, pass.pass)
		record.source == block.raw_span || continue
		applicable(check(harness, record)) || continue
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
		record = latest_applicable_record(harness, item.block, other_pass)
		(record === nothing || record.outcome != :positive) && continue
		for assertion in assertions, existing in record.assertions
			Source.covers(assertion.span, existing.span) && Source.covers(existing.span, assertion.span) && throw(ReviewItem(
				item.item_id, pass.pass, "structural_conflict",
				"coincident node span $(assertion.span) with $(other_pass.pass)",
			))
			Source.laminar(assertion.span, existing.span) || throw(ReviewItem(
				item.item_id, pass.pass, "structural_conflict",
				"node span $(assertion.span) crosses $(other_pass.pass) span $(existing.span)",
			))
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
	for outer in eachindex(residuals), inner in (outer + 1):lastindex(residuals)
		Source.disjoint(residuals[outer], residuals[inner]) ||
			throw(ReviewItem(item.item_id, pass.pass, "residuals_overlap",
				"$(residuals[outer]) and $(residuals[inner])"))
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
		form_bearing(pass.node_type) ||
			throw(ReviewItem(item.item_id, pass.pass, "schema_violation",
				"$(node_type_name(pass.node_type)) is not form-bearing"))
		push!(assertions, NodeAssertion(string(uuid4()), pass.node_type, span, nothing, constituents))
	end
	assertions
end

"""
	build_scopes(harness, item, pass, decision)

The marker selection must land on an actual qualification marker element, not on arbitrary prose:
an adjudicator may say where a printed label reaches, not invent a label the source does not
print.
"""
function build_scopes(
	harness::Harness, item::AdjudicationItem, pass::PassDefinition, decision::Decision,
)::Vector{ScopeAssertion}
	document = document_for(harness, item.block)
	markers = marker_spans(harness, item.block)
	scopes = ScopeAssertion[]
	for selection in decision.scopes
		selected = resolve_selection(harness, item, pass, selection.marker, "marker")
		# The adjudicator selects the printed label; the durable anchor is the marker element that
		# carries it, so the record matches what the resolver extracted rather than a text slice.
		index = findfirst(candidate -> Source.covers(candidate, selected), markers)
		index === nothing &&
			throw(ReviewItem(item.item_id, pass.pass, "not_a_marker",
				"$(repr(selection.marker)) is not a qualification marker in this block"))
		marker = markers[index]
		target = resolve_selection(harness, item, pass, selection.target, "scope target")
		Source.disjoint(marker, target) ||
			throw(ReviewItem(item.item_id, pass.pass, "scope_contains_marker",
				"a marker may not be inside the material it governs"))
		push!(scopes, ScopeAssertion(string(uuid4()), marker, target))
	end
	scopes
end

function marker_spans(harness::Harness, block::Census.SourceBlock)::Vector{RawSpan}
	document = document_for(harness, block)
	node = element_at(document, block.view_span)
	spans = RawSpan[]
	for child in XML.children(node)
		XML.nodetype(child) == XML.Element && XML.tag(child) in ("semantique", "nature") || continue
		push!(spans, Source.node_raw_span(document, child)[1])
	end
	spans
end

"""
	partition_gap(document, block, projection, spans)

The first stretch of source-visible material in the projected target claimed by none of `spans`, or
`nothing` when the partition is complete. This is what makes an exhaustive claim checked rather
than trusted: a producer asserting exhaustion over material it never accounted for fails closed
instead of licensing a derived sense.
"""
function partition_gap(
	document::Source.SourceDocument, block::Census.SourceBlock, projection::ProjectedView,
	spans::Vector{RawSpan},
)::Union{Nothing, String}
	claimed = falses(ncodeunits(projection.text))
	for span in spans
		mark_claimed!(claimed, projection, document, span)
	end
	for segment in projection.segments
		segment.synthetic && continue
		for position in segment.projected_start:(segment.projected_end - 1)
			claimed[position] && continue
			isspace(projection.text[thisind(projection.text, position)]) && continue
			return String(strip(SubString(
				projection.text,
				thisind(projection.text, position),
				prevind(projection.text, min(segment.projected_end, position + 40)),
			)))
		end
	end
	nothing
end

function mark_claimed!(
	claimed::BitVector, projection::ProjectedView,
	document::Source.SourceDocument, span::RawSpan,
)
	view = Source.to_view(document.transform, span)
	for segment in projection.segments
		segment.synthetic && continue
		segment.view_end <= view.start_byte && continue
		segment.view_start >= view.end_byte && continue
		start_byte = segment.projected_start + max(0, view.start_byte - segment.view_start)
		end_byte = segment.projected_end - max(0, segment.view_end - view.end_byte)
		for position in start_byte:(end_byte - 1)
			1 <= position <= length(claimed) && (claimed[position] = true)
		end
	end
	nothing
end

"""
	verify_partition(harness, item, pass, decision, assertions, residuals)

An exhaustive claim is checked here, not merely at build. Every source-visible character of the
target must be claimed by an asserted node span or an explicit residual span; a claim over material
the producer did not account for is rejected while there is still an item to re-author, rather than
becoming a review row discovered at the next full build.
"""
function verify_partition(
	harness::Harness, item::AdjudicationItem, pass::PassDefinition, decision::Decision,
	assertions::Vector{NodeAssertion}, residuals::Vector{RawSpan},
)
	decision.exhaustive || return nothing
	document = document_for(harness, item.block)
	unaccounted = partition_gap(
		document, item.block, item.projection,
		vcat(RawSpan[assertion.span for assertion in assertions], residuals),
	)
	unaccounted === nothing || throw(ReviewItem(
		item.item_id, pass.pass, "incomplete_partition",
		"exhaustive claim leaves $(repr(unaccounted)) unaccounted for",
	))
	nothing
end

"""
	commit(harness, pass, item, decision; decision_procedure, decision_reference)

Validate a verdict and mint the anchored record. Nothing about source identity is supplied by the
caller: spans come from projected selections, hashes and ids from repository data. How the verdict
was reached is likewise not the harness's business; it records the procedure's name and an opaque
reference and interprets neither.
"""
function commit(
	harness::Harness, pass::PassDefinition, item::AdjudicationItem, decision::Decision;
	decision_procedure::AbstractString = "", decision_reference = nothing,
	now::AbstractString = timestamp(),
)::ExaminationRecord
	decision.outcome in outcomes ||
		throw(ReviewItem(item.item_id, pass.pass, "schema_violation", "unknown outcome $(decision.outcome)"))
	decision.outcome == :positive || (isempty(decision.selections) && isempty(decision.scopes)) ||
		throw(ReviewItem(item.item_id, pass.pass, "schema_violation", "assertions on a non-positive outcome"))
	decision.outcome == :positive || !decision.exhaustive ||
		throw(ReviewItem(item.item_id, pass.pass, "schema_violation", "exhaustive claim without a positive outcome"))
	# The pass declares whether its examination is exhaustive extraction. A claim the pass does not
	# make is meaningless and would be stored unread; a claim the pass requires cannot be omitted,
	# because closure would then decline to derive and the omission would surface only at the next
	# build, as a review row rather than a rejected item.
	decision.exhaustive && !pass.exhaustive_extraction &&
		throw(ReviewItem(item.item_id, pass.pass, "schema_violation",
			"exhaustive claim from a pass that does not perform exhaustive extraction"))
	decision.outcome != :positive || !pass.exhaustive_extraction || decision.exhaustive ||
		throw(ReviewItem(item.item_id, pass.pass, "schema_violation",
			"positive outcome without the exhaustive claim this pass requires"))
	decision.outcome != :positive || !isempty(decision.selections) || !isempty(decision.scopes) ||
		throw(ReviewItem(item.item_id, pass.pass, "schema_violation", "positive outcome with no assertion"))
	isempty(decision.scopes) || pass.node_type === nothing ||
		throw(ReviewItem(item.item_id, pass.pass, "schema_violation",
			"scope assertions from a structural pass"))
	isempty(decision.selections) || pass.node_type !== nothing ||
		throw(ReviewItem(item.item_id, pass.pass, "schema_violation",
			"node assertions from a pass with no node type"))

	document = document_for(harness, item.block)
	assertions = build_assertions(harness, item, pass, decision)
	scopes = build_scopes(harness, item, pass, decision)
	validate_geometry(item, pass, assertions)
	validate_against_store(harness, item, pass, assertions)
	residuals = RawSpan[
		resolve_selection(harness, item, pass, residual, "residual") for residual in decision.residuals
	]
	validate_residuals(item, pass, residuals, assertions)
	verify_partition(harness, item, pass, decision, assertions, residuals)

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
		decision.outcome,
		decision.exhaustive,
		assertions,
		scopes,
		residuals,
		decision_procedure,
		decision_reference,
		now,
		decision.notes,
	)
end

timestamp()::String = Dates.format(Dates.now(Dates.UTC), "yyyy-mm-ddTHH:MM:SSZ")

function valid_record_shape(
	harness::Harness, record::ExaminationRecord, pass::PassDefinition, block::Census.SourceBlock,
)::Bool
	record.outcome in outcomes || return false
	if record.outcome == :positive
		isempty(record.assertions) && isempty(record.scopes) && return false
	else
		isempty(record.assertions) || return false
		isempty(record.scopes) || return false
		record.exhaustive && return false
	end
	if pass.node_type === nothing
		isempty(record.assertions) || return false
	else
		isempty(record.scopes) || return false
		all(assertion -> typeof(assertion.node_type) == typeof(pass.node_type), record.assertions) || return false
	end
	for assertion in record.assertions
		Source.covers(record.source, assertion.span) || return false
		for constituent in assertion.constituents
			Source.covers(assertion.span, constituent.span) || return false
		end
	end
	for outer in eachindex(record.assertions), inner in (outer + 1):lastindex(record.assertions)
		Source.covers(record.assertions[outer].span, record.assertions[inner].span) &&
		Source.covers(record.assertions[inner].span, record.assertions[outer].span) && return false
		Source.laminar(record.assertions[outer].span, record.assertions[inner].span) || return false
	end
	for residual in record.residuals
		Source.covers(record.source, residual) || return false
		all(assertion -> Source.disjoint(residual, assertion.span), record.assertions) || return false
	end
	for outer in eachindex(record.residuals), inner in (outer + 1):lastindex(record.residuals)
		Source.disjoint(record.residuals[outer], record.residuals[inner]) || return false
	end
	for scope in record.scopes
		Source.covers(record.source, scope.marker) || return false
		Source.covers(record.source, scope.target) || return false
		Source.disjoint(scope.marker, scope.target) || return false
	end
	if !isempty(record.scopes)
		markers = marker_spans(harness, block)
		all(scope -> scope.marker in markers, record.scopes) || return false
	end
	true
end

function check(harness::Harness, record::ExaminationRecord)::Symbol
	pass = pass_definition(record.pass)
	pass === nothing && return :unknown_pass
	record.pass_version == pass.pass_version || return :pass_version_mismatch
	record.population == pass.population || return :population_mismatch
	record.population_version == pass.population_version || return :population_version_mismatch
	record.projection == pass.projection || return :projection_mismatch
	record.projection_version == pass.projection_version || return :projection_version_mismatch
	document = get(harness.documents, record.source.file, nothing)
	document === nothing && return :raw_mismatch
	Source.covers(RawSpan(record.source.file, 1, ncodeunits(document.raw_text) + 1), record.source) ||
		return :raw_mismatch
	Source.raw_sha256(document, record.source) == record.raw_sha256 || return :raw_mismatch
	block = get(harness.blocks, anchor_key(record.source), nothing)
	block === nothing && return :missing_block
	population_predicate(pass.population)(block.kind) || return :ineligible_target
	record.synthetic_boundary == block.synthetic_boundary || return :synthetic_boundary_mismatch
	valid_record_shape(harness, record, pass, block) || return :record_schema_mismatch
	projection = project(document, element_at(document, block.view_span))
	projection.name == record.projection || return :projection_mismatch
	projection.version == record.projection_version || return :projection_version_mismatch
	view_sha256(projection) == record.view_sha256 || return :view_mismatch
	all(reference -> Source.covers(record.source, reference.span), record.context) ||
		return :record_schema_mismatch
	:valid
end

fatal(result::Symbol)::Bool = result == :raw_mismatch
applicable(result::Symbol)::Bool = result == :valid
