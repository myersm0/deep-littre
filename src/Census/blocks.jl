"""
A block kind is source syntax, never semantic classification. Kinds are singleton types
rather than an enum so that an unhandled kind fails loudly at the dispatch site instead of
falling through a catch-all branch.
"""
abstract type BlockKind end

struct Indent <: BlockKind end
struct Variante <: BlockKind end
struct ResumeIndent <: BlockKind end
struct ResumeVariante <: BlockKind end
struct RubriqueIndent <: BlockKind end
struct RubriqueVariante <: BlockKind end
struct EnteteNature <: BlockKind end

kind_name(::Indent) = "indent"
kind_name(::Variante) = "variante"
kind_name(::ResumeIndent) = "resume_indent"
kind_name(::ResumeVariante) = "resume_variante"
kind_name(::RubriqueIndent) = "rubrique_indent"
kind_name(::RubriqueVariante) = "rubrique_variante"
kind_name(::EnteteNature) = "entete_nature"

const block_kinds = (
	Indent(), Variante(), ResumeIndent(), ResumeVariante(),
	RubriqueIndent(), RubriqueVariante(), EnteteNature(),
)

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

identifier(span::RawSpan)::String = string(span.file, ':', span.start_byte, ':', span.end_byte)

struct Context
	within_rubrique::Bool
	within_resume::Bool
	entry_id::String
	parent_id::Union{Nothing, String}
end

descend(context::Context, parent_id::String) =
	Context(context.within_rubrique, context.within_resume, context.entry_id, parent_id)

function block_kind(name::AbstractString, context::Context)::BlockKind
	if name == "indent"
		context.within_resume ? ResumeIndent() :
			context.within_rubrique ? RubriqueIndent() : Indent()
	elseif name == "variante"
		context.within_resume ? ResumeVariante() :
			context.within_rubrique ? RubriqueVariante() : Variante()
	else
		error("no block kind for element <$(name)>")
	end
end

function homograph_index(node::XML.FlatNode)::Union{Nothing, Int}
	value = Source.attribute(node, "sens")
	value === nothing && return nothing
	tryparse(Int, value)
end

function scan!(
	document::Source.SourceDocument,
	rubriques::Vector{SourceRubrique},
	anomalies::Vector{String},
	node::XML.FlatNode,
	context::Context,
)::Vector{SourceBlock}
	blocks = SourceBlock[]
	for child in Source.elements(node)
		name = XML.tag(child)
		if name == "rubrique"
			push!(rubriques, build_rubrique(document, rubriques, anomalies, child, context))
		elseif name == "indent" || name == "variante"
			push!(blocks, build_block(document, rubriques, anomalies, child, context, name))
		elseif name == "résumé"
			inner = Context(context.within_rubrique, true, context.entry_id, context.parent_id)
			append!(blocks, scan!(document, rubriques, anomalies, child, inner))
		elseif name == "entete"
			for nature in Source.element_children(child, "nature")
				push!(blocks, leaf_block(document, nature, EnteteNature(), context))
			end
		elseif name == "prononciation" || name == "nature"
			continue
		else
			append!(blocks, scan!(document, rubriques, anomalies, child, context))
		end
	end
	blocks
end

function leaf_block(
	document::Source.SourceDocument, node::XML.FlatNode, kind::BlockKind, context::Context,
)::SourceBlock
	view = Source.node_view_span(document, node)
	(raw, synthetic) = Source.node_raw_span(document, node)
	SourceBlock(
		identifier(raw), kind, raw, view, synthetic,
		context.entry_id, context.parent_id, SourceBlock[],
	)
end

function build_block(
	document::Source.SourceDocument,
	rubriques::Vector{SourceRubrique},
	anomalies::Vector{String},
	node::XML.FlatNode,
	context::Context,
	name::AbstractString,
)::SourceBlock
	kind = block_kind(name, context)
	check_resume_marking(document, node, kind, context, anomalies)
	view = Source.node_view_span(document, node)
	(raw, synthetic) = Source.node_raw_span(document, node)
	source_id = identifier(raw)
	children = scan!(document, rubriques, anomalies, node, descend(context, source_id))
	SourceBlock(source_id, kind, raw, view, synthetic, context.entry_id, context.parent_id, children)
end

function check_resume_marking(
	document::Source.SourceDocument,
	node::XML.FlatNode,
	kind::BlockKind,
	context::Context,
	anomalies::Vector{String},
)
	XML.tag(node) == "variante" || return nothing
	marked = Source.attribute(node, "option") == "résumé"
	if marked && !(kind isa ResumeVariante)
		push!(anomalies, "$(context.entry_id): variante marked option=résumé outside <résumé>")
	elseif !marked && kind isa ResumeVariante
		push!(anomalies, "$(context.entry_id): variante inside <résumé> without option=résumé")
	end
	nothing
end

function build_rubrique(
	document::Source.SourceDocument,
	rubriques::Vector{SourceRubrique},
	anomalies::Vector{String},
	node::XML.FlatNode,
	context::Context,
)::SourceRubrique
	view = Source.node_view_span(document, node)
	(raw, _) = Source.node_raw_span(document, node)
	source_id = identifier(raw)
	name = something(Source.attribute(node, "nom"), "")
	inner = Context(true, false, context.entry_id, source_id)
	blocks = scan!(document, rubriques, anomalies, node, inner)
	SourceRubrique(source_id, name, raw, view, context.entry_id, blocks)
end

function build_entry(
	document::Source.SourceDocument, node::XML.FlatNode, anomalies::Vector{String},
)::SourceEntry
	view = Source.node_view_span(document, node)
	(raw, _) = Source.node_raw_span(document, node)
	source_id = identifier(raw)
	rubriques = SourceRubrique[]
	context = Context(false, false, source_id, nothing)
	blocks = scan!(document, rubriques, anomalies, node, context)
	SourceEntry(
		source_id,
		something(Source.attribute(node, "terme"), ""),
		homograph_index(node),
		raw,
		view,
		blocks,
		rubriques,
	)
end

function census(document::Source.SourceDocument)::DocumentCensus
	anomalies = String[]
	entries = SourceEntry[]
	for node in Source.element_children(Source.root_element(document), "entree")
		push!(entries, build_entry(document, node, anomalies))
	end
	DocumentCensus(document.file, entries, anomalies)
end

function census(documents::Vector{Source.SourceDocument}; progress = nothing)::CorpusCensus
	results = DocumentCensus[]
	for document in documents
		elapsed = @elapsed result = census(document)
		push!(results, result)
		progress === nothing ||
			progress(document.file, length(result.entries), length(all_blocks(result)), elapsed)
	end
	CorpusCensus(results)
end

function walk_blocks!(collected::Vector{SourceBlock}, blocks::Vector{SourceBlock})
	for block in blocks
		push!(collected, block)
		walk_blocks!(collected, block.children)
	end
	collected
end

function all_blocks(entry::SourceEntry)::Vector{SourceBlock}
	collected = SourceBlock[]
	walk_blocks!(collected, entry.blocks)
	for rubrique in entry.rubriques
		walk_blocks!(collected, rubrique.blocks)
	end
	collected
end

all_blocks(document::DocumentCensus)::Vector{SourceBlock} =
	reduce(vcat, (all_blocks(entry) for entry in document.entries); init = SourceBlock[])

all_blocks(corpus::CorpusCensus)::Vector{SourceBlock} =
	reduce(vcat, (all_blocks(document) for document in corpus.documents); init = SourceBlock[])

all_entries(corpus::CorpusCensus)::Vector{SourceEntry} =
	reduce(vcat, (document.entries for document in corpus.documents); init = SourceEntry[])

anomalies(corpus::CorpusCensus)::Vector{String} =
	reduce(vcat, (document.anomalies for document in corpus.documents); init = String[])

function counts(blocks::Vector{SourceBlock})::Dict{String, Int}
	tally = Dict(kind_name(kind) => 0 for kind in block_kinds)
	for block in blocks
		tally[kind_name(block.kind)] += 1
	end
	tally
end

counts(corpus::CorpusCensus)::Dict{String, Int} = counts(all_blocks(corpus))

"""
	population_hash(blocks)

Computed over the ordered durable anchors, so a changed denominator cannot present itself
as the same population under an unchanged count.
"""
function population_hash(blocks::Vector{SourceBlock})::String
	context = SHA.SHA256_CTX()
	for block in blocks
		SHA.update!(context, codeunits(string(identifier(block.raw_span), ':', kind_name(block.kind), '\n')))
	end
	bytes2hex(SHA.digest!(context))
end
