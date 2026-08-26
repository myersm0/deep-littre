using Test
using DeepLittre
using XML
using DeepLittre: Source, Census, Adjudication, Resolve, Render

const repository_root = normpath(joinpath(@__DIR__, ".."))
const fixture_root = joinpath(@__DIR__, "fixtures")
const corpus_source = joinpath(@__DIR__, "corpus", "source")
const corpus_adjudication = joinpath(@__DIR__, "corpus", "adjudication")

function all_qualifications(entry)
	found = []
	gather(nodes) = for node in nodes
		append!(found, node.qualifications)
		gather(node.children)
	end
	gather(entry.nodes)
	append!(found, entry.grammar)
	found
end

source_of(documents, block) = first(filter(d -> d.file == block.raw_span.file, documents))

function build_harness(documents, corpus)
	harness = Adjudication.Harness(documents, corpus, Adjudication.Store(mktempdir()))
	Adjudication.initialize_store!(harness)
	harness
end

function angoisse_block(harness, corpus)
	first(filter(Census.all_blocks(corpus)) do block
		block.kind isa Census.Indent || return false
		document = harness.documents[block.raw_span.file]
		occursin("Avaler des poires", Source.slice(document.raw_text, block.raw_span))
	end)
end

@testset "DeepLittre" begin
	include("source/test_spans.jl")
	include("source/test_encoding.jl")
	include("source/test_patches.jl")
	include("source/test_transform.jl")
	include("source/test_parser.jl")
	include("census/test_census.jl")
	include("adjudication/test_projection.jl")
	include("adjudication/test_harness.jl")
	include("adjudication/test_store.jl")
	include("adjudication/test_committed_store.jl")
	include("adjudication/test_voice_variant.jl")
	include("adjudication/test_scope.jl")
	include("resolve/test_resolve.jl")
	include("resolve/test_etymology.jl")
	include("resolve/test_authors.jl")
	include("render/test_render.jl")
	include("render/test_rubriques.jl")
end
