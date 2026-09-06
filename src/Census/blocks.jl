# ===== block kinds =====

abstract type BlockKind end

struct Indent <: BlockKind end
struct Variante <: BlockKind end
struct ResumeIndent <: BlockKind end
struct ResumeVariante <: BlockKind end
struct RubriqueIndent <: BlockKind end
struct RubriqueVariante <: BlockKind end
struct RubriqueDirect <: BlockKind end
struct EnteteIndent <: BlockKind end
struct EnteteNature <: BlockKind end

kind_name(::Indent) = "indent"
kind_name(::Variante) = "variante"
kind_name(::ResumeIndent) = "resume_indent"
kind_name(::ResumeVariante) = "resume_variante"
kind_name(::RubriqueIndent) = "rubrique_indent"
kind_name(::RubriqueVariante) = "rubrique_variante"
kind_name(::RubriqueDirect) = "rubrique_direct"
kind_name(::EnteteIndent) = "entete_indent"
kind_name(::EnteteNature) = "entete_nature"

const block_kinds = (
	Indent(), Variante(), ResumeIndent(), ResumeVariante(), RubriqueIndent(),
	RubriqueVariante(), RubriqueDirect(), EnteteIndent(), EnteteNature(),
)


# ===== census records =====

struct SourceBlock
	source_id::String
	kind::BlockKind
	raw_span::RawSpan
	view_span::ViewSpan
	synthetic_boundary::Bool
	entry_id::String
	parent_id::Union{Nothing, String}
	children::Vector{SourceBlock}
end

struct SourceRubrique
	source_id::String
	name::String
	raw_span::RawSpan
	view_span::ViewSpan
	entry_id::String
	parent_id::Union{Nothing, String}
	blocks::Vector{SourceBlock}
end

struct SourceEntry
	source_id::String
	headword::String
	homograph::Union{Nothing, Int}
	raw_span::RawSpan
	view_span::ViewSpan
	blocks::Vector{SourceBlock}
	rubriques::Vector{SourceRubrique}
end

struct DocumentCensus
	file::String
	entries::Vector{SourceEntry}
	anomalies::Vector{String}
end

struct CorpusCensus
	documents::Vector{DocumentCensus}
end


# ===== source elements =====

abstract type SourceElement end
abstract type BlockElement <: SourceElement end

struct IndentElement <: BlockElement end
struct VarianteElement <: BlockElement end
struct RubriqueElement <: SourceElement end
struct ResumeElement <: SourceElement end
struct EnteteElement <: SourceElement end
struct NatureElement <: SourceElement end
struct PrononciationElement <: SourceElement end
struct OtherElement <: SourceElement end

const source_elements = Dict{String, SourceElement}(
	"indent" => IndentElement(),
	"variante" => VarianteElement(),
	"rubrique" => RubriqueElement(),
	"résumé" => ResumeElement(),
	"entete" => EnteteElement(),
	"nature" => NatureElement(),
	"prononciation" => PrononciationElement(),
)

source_element(name::AbstractString)::SourceElement =
	get(source_elements, name, OtherElement())


# ===== ancestry context =====

# TODO: consider using a kwdef
struct Context
	within_rubrique::Bool
	within_resume::Bool
	within_entete::Bool
	entry_id::String
	parent_id::Union{Nothing, String}
end

Context(entry_id::AbstractString) = Context(false, false, false, entry_id, nothing)

descend(context::Context, parent_id::AbstractString) = Context(
	context.within_rubrique, context.within_resume, false, context.entry_id, parent_id,
)

enter_rubrique(context::Context, source_id::AbstractString) =
	Context(true, false, false, context.entry_id, source_id)

enter_resume(context::Context) = Context(
	context.within_rubrique, true, context.within_entete,
	context.entry_id, context.parent_id,
)

enter_entete(context::Context) = Context(
	context.within_rubrique, context.within_resume, true,
	context.entry_id, context.parent_id,
)

function block_kind(::IndentElement, context::Context)::BlockKind
	context.within_entete && return EnteteIndent()
	context.within_resume && return ResumeIndent()
	context.within_rubrique && return RubriqueIndent()
	return Indent()
end

function block_kind(::VarianteElement, context::Context)::BlockKind
	context.within_resume && return ResumeVariante()
	context.within_rubrique && return RubriqueVariante()
	return Variante()
end


# ===== scanning =====

struct CensusBuilder
	document::Source.SourceDocument
	rubriques::Vector{SourceRubrique}
	anomalies::Vector{String}
end

function scan!(
	builder::CensusBuilder, node::XML.FlatNode, context::Context,
)::Vector{SourceBlock}
	blocks = SourceBlock[]
	for child in Source.elements(node)
		element = source_element(XML.tag(child))
		scan_child!(element, builder, blocks, child, context)
	end
	return blocks
end

scan_child!(element::BlockElement, builder, blocks, node, context) =
	push!(blocks, build_block(element, builder, node, context))

scan_child!(::RubriqueElement, builder, blocks, node, context) =
	push!(builder.rubriques, build_rubrique(builder, node, context))

scan_child!(::ResumeElement, builder, blocks, node, context) =
	append!(blocks, scan!(builder, node, enter_resume(context)))

scan_child!(::EnteteElement, builder, blocks, node, context) =
	append!(blocks, scan!(builder, node, enter_entete(context)))

function scan_child!(::NatureElement, builder, blocks, node, context)
	context.within_entete || return blocks
	return push!(blocks, leaf_block(builder, node, EnteteNature(), context))
end

scan_child!(::PrononciationElement, builder, blocks, node, context) = blocks

scan_child!(::OtherElement, builder, blocks, node, context) =
	append!(blocks, scan!(builder, node, context))


# ===== building blocks =====

function leaf_block(
	builder::CensusBuilder, node::XML.FlatNode, kind::BlockKind, context::Context,
)::SourceBlock
	document = builder.document
	view_span = Source.node_view_span(document, node)
	(raw_span, synthetic) = Source.node_raw_span(document, node)
	return SourceBlock(
		anchor_id(raw_span), 
		kind, 
		raw_span, 
		view_span, 
		synthetic,
		context.entry_id, 
		context.parent_id, 
		SourceBlock[],
	)
end

function build_block(
	element::BlockElement, builder::CensusBuilder, node::XML.FlatNode, context::Context,
)::SourceBlock
	document = builder.document
	kind = block_kind(element, context)
	check_resume_marking(builder, node, kind, context)
	view_span = Source.node_view_span(document, node)
	(raw_span, synthetic) = Source.node_raw_span(document, node)
	source_id = anchor_id(raw_span)
	children = scan!(builder, node, descend(context, source_id))
	return SourceBlock(
		source_id, 
		kind, 
		raw_span, 
		view_span, 
		synthetic,
		context.entry_id, 
		context.parent_id, 
		children,
	)
end

function check_resume_marking(
	builder::CensusBuilder, node::XML.FlatNode, kind::BlockKind, context::Context,
)
	XML.tag(node) == "variante" || return nothing
	marked = Source.attribute(node, "option") == "résumé"
	if marked && !(kind isa ResumeVariante)
		push!(
			builder.anomalies,
			"$(context.entry_id): variante marked option=résumé outside <résumé>",
		)
	elseif !marked && kind isa ResumeVariante
		push!(
			builder.anomalies,
			"$(context.entry_id): variante inside <résumé> without option=résumé",
		)
	end
	return nothing
end

const rubrique_direct_exclusions = ("indent", "variante", "rubrique", "résumé", "cit")

function has_rubrique_direct_content(
	document::Source.SourceDocument, node::XML.FlatNode,
)::Bool
	for child in XML.children(node)
		nodetype = XML.nodetype(child)
		if nodetype == XML.Text
			view_span = Source.node_view_span(document, child)
			text = Source.slice(document.parser_view, view_span)
			isempty(strip(XML.unescape(text))) || return true
		elseif nodetype == XML.Element
			XML.tag(child) in rubrique_direct_exclusions && continue
			has_rubrique_direct_content(document, child) && return true
		end
	end
	return false
end

function rubrique_direct_block(
	builder::CensusBuilder, node::XML.FlatNode, context::Context, rubrique_id::String,
)::SourceBlock
	document = builder.document
	view_span = Source.node_view_span(document, node)
	(raw_span, synthetic) = Source.node_raw_span(document, node)
	return SourceBlock(
		string(anchor_id(raw_span), ":direct"), 
		RubriqueDirect(), 
		raw_span, 
		view_span,
		synthetic, 
		context.entry_id, 
		rubrique_id, 
		SourceBlock[],
	)
end

function build_rubrique(
	builder::CensusBuilder, node::XML.FlatNode, context::Context,
)::SourceRubrique
	document = builder.document
	view_span = Source.node_view_span(document, node)
	(raw_span, _) = Source.node_raw_span(document, node)
	source_id = anchor_id(raw_span)
	name = something(Source.attribute(node, "nom"), "")
	inner = enter_rubrique(context, source_id)
	blocks = scan!(builder, node, inner)
	if has_rubrique_direct_content(document, node)
		pushfirst!(blocks, rubrique_direct_block(builder, node, inner, source_id))
	end
	return SourceRubrique(
		source_id, 
		name, 
		raw_span, 
		view_span,
		context.entry_id, 
		context.parent_id, 
		blocks,
	)
end

function homograph_index(node::XML.FlatNode)::Union{Nothing, Int}
	value = Source.attribute(node, "sens")
	isnothing(value) && return nothing
	return tryparse(Int, value)
end

function build_entry(
	document::Source.SourceDocument, node::XML.FlatNode, anomalies::Vector{String},
)::SourceEntry
	view_span = Source.node_view_span(document, node)
	(raw_span, _) = Source.node_raw_span(document, node)
	source_id = anchor_id(raw_span)
	builder = CensusBuilder(document, SourceRubrique[], anomalies)
	blocks = scan!(builder, node, Context(source_id))
	return SourceEntry(
		source_id,
		something(Source.attribute(node, "terme"), ""),
		homograph_index(node),
		raw_span,
		view_span,
		blocks,
		builder.rubriques,
	)
end


# ===== census =====

function census(document::Source.SourceDocument)::DocumentCensus
	anomalies = String[]
	entries = SourceEntry[]
	for node in Source.element_children(Source.root_element(document), "entree")
		push!(entries, build_entry(document, node, anomalies))
	end
	return DocumentCensus(document.file, entries, anomalies)
end

function census(
	documents::Vector{Source.SourceDocument}; progress = nothing,
)::CorpusCensus
	results = DocumentCensus[]
	for document in documents
		elapsed = @elapsed result = census(document)
		push!(results, result)
		isnothing(progress) || progress(
			document.file, length(result.entries), length(all_blocks(result)), elapsed,
		)
	end
	return CorpusCensus(results)
end


# ===== aggregation =====

function walk_blocks!(collected::Vector{SourceBlock}, blocks::Vector{SourceBlock})
	for block in blocks
		push!(collected, block)
		walk_blocks!(collected, block.children)
	end
	return collected
end

function all_blocks(entry::SourceEntry)::Vector{SourceBlock}
	collected = SourceBlock[]
	walk_blocks!(collected, entry.blocks)
	for rubrique in entry.rubriques
		walk_blocks!(collected, rubrique.blocks)
	end
	return collected
end

all_blocks(document::DocumentCensus)::Vector{SourceBlock} = reduce(
	vcat, (all_blocks(entry) for entry in document.entries); init = SourceBlock[],
)

all_blocks(corpus::CorpusCensus)::Vector{SourceBlock} = reduce(
	vcat, (all_blocks(document) for document in corpus.documents); init = SourceBlock[],
)

all_entries(corpus::CorpusCensus)::Vector{SourceEntry} = reduce(
	vcat, (document.entries for document in corpus.documents); init = SourceEntry[],
)

anomalies(corpus::CorpusCensus)::Vector{String} = reduce(
	vcat, (document.anomalies for document in corpus.documents); init = String[],
)

function counts(blocks::Vector{SourceBlock})::Dict{String, Int}
	tally = Dict(kind_name(kind) => 0 for kind in block_kinds)
	for block in blocks
		tally[kind_name(block.kind)] += 1
	end
	return tally
end

counts(corpus::CorpusCensus)::Dict{String, Int} = counts(all_blocks(corpus))

function population_hash(blocks::Vector{SourceBlock})::String
	digest = SHA.SHA256_CTX()
	for block in blocks
		anchored_kind = "$(anchor_id(block.raw_span)):$(kind_name(block.kind))\n"
		SHA.update!(digest, codeunits(anchored_kind))
	end
	return bytes2hex(SHA.digest!(digest))
end
